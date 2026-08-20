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
/// Chrome root-caused by direct AX inspection: `AXEnhancedUserInterface`/
/// `AXManualAccessibility` do make the value itself readable on demand
/// (confirmed correct via a live dump — typing into a page's search box
/// showed up right away in `kAXValueAttribute`), but Chromium's web content
/// doesn't reliably fire either `kAXFocusedUIElementChangedNotification` or
/// `kAXValueChangedNotification` — confirmed both by a live end-to-end
/// test: the value was readable on demand throughout, yet nothing was ever
/// recorded, meaning `trackedElement` never even got pointed at the field
/// in the first place. `pollTrackedElement` below re-derives both facts
/// itself on a short timer — which element is currently focused, and what
/// its value is — instead of waiting on notifications that may never
/// come. Terminal apps are a separate case — their AX value isn't settable
/// at all, not just non-notifying (see `TerminalKeyTracker` for that path
/// instead).
///
/// ponytail: because Chrome never notifies, polling is the *only* signal
/// for its web content — and a poll can land mid-composition (a search box
/// showing a live, still-changing Hangul syllable, or a grayed-out
/// autocomplete suggestion appended after what was actually typed). Only
/// ingesting a polled value once it reads back identically on the next
/// tick (`lastPolledValue` below) filters out most of that churn, but not
/// all of it — confirmed live: an unlucky poll still occasionally split a
/// word (a rendered autocomplete suggestion briefly extending, then
/// retracting, the field's value in a way that isn't a simple append).
/// Good enough that real words get through; occasional fragmentation in
/// autocomplete-heavy fields is an accepted remaining gap.
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
    private var currentAppElement: AXUIElement?
    private var trackedElement: AXUIElement?
    private var scanner = IncrementalWordScanner()
    private var activationToken: NSObjectProtocol?
    private var pollTimer: Timer?
    /// Last value seen by a poll (not a notification) — a polled value only
    /// gets ingested once it matches this, i.e. it read back unchanged on
    /// the next tick, which is what "composition/autocomplete settled"
    /// looks like from the outside.
    private var lastPolledValue: String?

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
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.pollTrackedElement()
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
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
        currentAppElement = appElement
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
        currentAppElement = nil
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
        lastPolledValue = nil
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

    /// Fallback for apps (Chromium's web content) that don't reliably fire
    /// either `kAXFocusedUIElementChangedNotification` or
    /// `kAXValueChangedNotification` — re-derives both directly on a short
    /// timer instead of waiting on notifications that may never come. A
    /// no-op most of the time: comparing to the already-tracked element via
    /// `CFEqual` skips the re-track when focus hasn't actually moved, and
    /// `IncrementalWordScanner.ingest` only reports genuinely new text past
    /// `processedText`, so a redundant poll costs a couple of cheap AX
    /// reads and nothing else.
    private func pollTrackedElement() {
        if let appElement = currentAppElement, let observer = appObserver,
           let focusedAny = Self.copyAttribute(appElement, kAXFocusedUIElementAttribute) {
            let focused = focusedAny as! AXUIElement
            let alreadyTracked = trackedElement.map { CFEqual(focused, $0) } ?? false
            if !alreadyTracked {
                trackFocusedElement(focused, observer: observer)
            }
        }
        guard let element = trackedElement,
              let value = Self.copyAttribute(element, kAXValueAttribute) as? String
        else { return }
        defer { lastPolledValue = value }
        guard value == lastPolledValue else { return }
        ingest(value)
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
