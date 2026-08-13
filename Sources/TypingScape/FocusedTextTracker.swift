import AppKit
import ApplicationServices

/// Tracks newly typed words by reading the *value* of the currently focused
/// UI element via the Accessibility API, instead of tapping raw keystrokes.
/// Composition (e.g. Hangul jamo -> syllable) happens above the raw key-event
/// layer, so reading the already-composed field value is what lets this see
/// real words instead of individual jamo.
///
/// ponytail: a word typed right before switching focus/app without a
/// trailing space/enter after it is dropped (never confirmed by a boundary
/// char). Also only works for apps that expose real AX text elements —
/// custom-drawn text (some games, canvas-based editors) won't report a
/// value at all. Good enough for normal app usage; revisit if that turns
/// out to matter.
///
/// ponytail: confirmed not working in Chrome even after requesting
/// `AXEnhancedUserInterface`/`AXManualAccessibility` — Chromium's AT
/// activation has shifted across versions and needs Accessibility
/// Inspector-based investigation to nail down properly. Left as a known gap
/// rather than guessing further; revisit with real inspection data.
/// Terminal apps are also unreliable (custom-rendered text, same root
/// cause as above).
/// Pure word-boundary diffing, kept separate from the AX plumbing so it can
/// be unit tested without a live accessibility session.
struct IncrementalWordScanner {
    private(set) var processedText: String

    init(processedText: String = "") {
        self.processedText = processedText
    }

    /// Only the newly-typed suffix since the last confirmed word boundary is
    /// scanned; `processedText` only advances up to that boundary, so a
    /// still-in-progress trailing word gets rescanned (harmlessly) next call.
    mutating func ingest(_ newValue: String, onWord: (String) -> Void) {
        scan(newValue, treatEndAsBoundary: false, onWord: onWord)
    }

    /// Same as `ingest`, but also confirms a still-in-progress trailing word
    /// (normally left pending until a real delimiter shows up). Call this
    /// right before the field stops being tracked — e.g. focus or app
    /// switch — since no delimiter will ever arrive for it after that.
    mutating func flush(_ newValue: String, onWord: (String) -> Void) {
        scan(newValue, treatEndAsBoundary: true, onWord: onWord)
    }

    private mutating func scan(_ newValue: String, treatEndAsBoundary: Bool, onWord: (String) -> Void) {
        guard newValue.hasPrefix(processedText) else {
            processedText = newValue
            return
        }
        var word = ""
        var lastBoundary = newValue.index(newValue.startIndex, offsetBy: processedText.count)
        var cursor = lastBoundary
        while cursor < newValue.endIndex {
            let ch = newValue[cursor]
            cursor = newValue.index(after: cursor)
            if ch.isLetter || ch.isNumber {
                word.append(ch)
            } else {
                if !word.isEmpty {
                    onWord(word)
                    word = ""
                }
                lastBoundary = cursor
            }
        }
        if treatEndAsBoundary, !word.isEmpty {
            onWord(word)
            lastBoundary = newValue.endIndex
        }
        processedText = String(newValue[..<lastBoundary])
    }
}

final class FocusedTextTracker {
    private let onWord: (String) -> Void
    private var appObserver: AXObserver?
    private var trackedElement: AXUIElement?
    private var scanner = IncrementalWordScanner()
    private var activationToken: NSObjectProtocol?

    init(onWord: @escaping (String) -> Void) {
        self.onWord = onWord
    }

    func start() {
        activationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.attach(toPid: app.processIdentifier)
        }
        if let frontPid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            attach(toPid: frontPid)
        }
    }

    func stop() {
        if let token = activationToken {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        detachObserver()
    }

    private func attach(toPid pid: pid_t) {
        detachObserver()

        var observer: AXObserver?
        guard AXObserverCreate(pid, Self.axCallback, &observer) == .success, let observer else { return }
        appObserver = observer

        let appElement = AXUIElementCreateApplication(pid)
        // Chromium/Electron apps (Chrome, Slack, VS Code, Discord, ...) keep
        // their full accessibility tree off unless an AT client explicitly
        // asks for it — without this, focused elements in those apps report
        // no value at all. Chromium checks a couple of differently-named
        // attributes depending on version; setting both is harmless no-ops
        // for apps that don't support either.
        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, appElement, kAXFocusedUIElementChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .commonModes)

        if let focused = Self.copyAttribute(appElement, kAXFocusedUIElementAttribute) {
            trackFocusedElement((focused as! AXUIElement), observer: observer)
        }
    }

    private func detachObserver() {
        if let observer = appObserver {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        flushTrackedElement()
        trackedElement = nil
        appObserver = nil
        scanner = IncrementalWordScanner()
    }

    private func trackFocusedElement(_ element: AXUIElement, observer: AXObserver) {
        if let previous = trackedElement {
            AXObserverRemoveNotification(observer, previous, kAXValueChangedNotification as CFString)
            flushTrackedElement()
        }
        // Read-only labels (settings rows, date-picker segments, list
        // items, ...) still report a `value` and can still receive focus,
        // but the user never typed it — tracking them recorded their whole
        // display text as if it were freshly typed. Only elements whose
        // value is actually settable are a real keyboard input. Password
        // fields are excluded outright, even though native AppKit secure
        // fields already mask their AX value — that masking isn't
        // guaranteed for every framework (e.g. a web login form rendered
        // through Chromium's accessibility bridge), so this is a second,
        // explicit backstop rather than relying on it alone.
        guard Self.isSettableTextValue(element), !Self.isSecureTextField(element) else {
            trackedElement = nil
            scanner = IncrementalWordScanner()
            return
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, element, kAXValueChangedNotification as CFString, refcon)
        trackedElement = element
        scanner = IncrementalWordScanner(processedText: (Self.copyAttribute(element, kAXValueAttribute) as? String) ?? "")
    }

    private static func isSettableTextValue(_ element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        return result == .success && settable.boolValue
    }

    private static func isSecureTextField(_ element: AXUIElement) -> Bool {
        (copyAttribute(element, kAXSubroleAttribute) as? String) == kAXSecureTextFieldSubrole
    }

    /// Confirms whatever's still pending in `trackedElement` as a final word
    /// before we stop watching it — otherwise a word typed right before a
    /// focus/app switch, with no trailing delimiter yet, is lost for good.
    private func flushTrackedElement() {
        guard let element = trackedElement,
              let finalValue = Self.copyAttribute(element, kAXValueAttribute) as? String else { return }
        scanner.flush(finalValue, onWord: onWord)
    }

    fileprivate func handleNotification(_ notification: CFString, element: AXUIElement) {
        guard let observer = appObserver else { return }
        switch notification as String {
        case kAXFocusedUIElementChangedNotification:
            if let focused = Self.copyAttribute(element, kAXFocusedUIElementAttribute) {
                trackFocusedElement((focused as! AXUIElement), observer: observer)
            }
        case kAXValueChangedNotification:
            guard let newValue = Self.copyAttribute(element, kAXValueAttribute) as? String else { return }
            ingest(newValue)
        default:
            break
        }
    }

    private func ingest(_ newValue: String) {
        scanner.ingest(newValue, onWord: onWord)
    }

    private static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static let axCallback: AXObserverCallback = { _, element, notification, refcon in
        guard let refcon else { return }
        Unmanaged<FocusedTextTracker>.fromOpaque(refcon).takeUnretainedValue().handleNotification(notification, element: element)
    }
}
