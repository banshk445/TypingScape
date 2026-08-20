import AppKit
import ApplicationServices

/// Terminal emulators render their buffer as a custom character grid
/// instead of exposing it through a normal text field's Accessibility
/// value the way `FocusedTextTracker` reads — and even where an AX value
/// exists, it's the whole visible screen (prompt, command output, scrollback)
/// with no way to tell what the user actually typed from what a program
/// printed. A raw keystroke tap is the only signal that's actually theirs.
///
/// Unlike `FocusedTextTracker`, this sees keys before IME composition —
/// a 2-beolsik Hangul input produces one raw jamo per keystroke here, not
/// the composed syllable — so `HangulComposer` reimplements that
/// composition step itself (same algorithm a real IME uses) rather than
/// recording raw jamo runs as "words".
///
/// ponytail: sees every keystroke while a terminal is frontmost, including
/// anything typed at a `sudo`/`ssh` password prompt. `WordStore.record`'s
/// existing spell-check filter is the only backstop — a password that
/// happens to be a real dictionary word isn't caught. Accepted trade-off
/// (user confirmed); revisit with a pause-after-sudo/ssh heuristic if it
/// turns out to matter.
final class TerminalKeyTracker {
    /// Not exhaustive — extend as new terminal apps come up. Deliberately
    /// excludes editors with an integrated terminal panel (VS Code, JetBrains
    /// IDEs, ...): bundle-ID-level detection can't tell "terminal panel
    /// focused" from "editor focused" within the same app, and those editors
    /// already work through `FocusedTextTracker`'s AX path for the parts
    /// that do expose a value — tapping raw keys for the whole app would
    /// double-record everything typed in the actual editor.
    private static let terminalBundleIdentifiers: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "co.zeit.hyper",
        "io.alacritty",
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "com.mitchellh.ghostty",
        "com.termius.mac",
        "com.panic.Prompt3",
    ]
    private static let deleteKeyCode: UInt16 = 51

    private let onWord: (String) -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activationToken: NSObjectProtocol?
    private var wordBuffer = ""
    private var composer = HangulComposer()
    private var isTerminalFrontmost = false

    init(onWord: @escaping (String) -> Void) {
        self.onWord = onWord
    }

    func start() {
        guard eventTap == nil else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let tracker = Unmanaged<TerminalKeyTracker>.fromOpaque(refcon).takeUnretainedValue()
                // The tap delivers these two regardless of the requested
                // event mask (a timeout, or the system deciding the tap is
                // unresponsive) — not a real keystroke, and NSEvent can't
                // represent them at all (crashes converting one). Only a
                // re-enable, nothing else.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    tracker.reEnableIfNeeded()
                    return Unmanaged.passUnretained(event)
                }
                guard type == .keyDown else { return Unmanaged.passUnretained(event) }
                tracker.handle(event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else { return }
        eventTap = tap
        // Starts disabled — only switched on while a terminal is actually
        // frontmost (below), so this taps nothing the rest of the time.
        CGEvent.tapEnable(tap: tap, enable: false)
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)

        activationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.setFrontmost(bundleIdentifier: app?.bundleIdentifier)
        }
        setFrontmost(bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    func stop() {
        if let token = activationToken { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        activationToken = nil
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        flushWord()
        isTerminalFrontmost = false
    }

    fileprivate func reEnableIfNeeded() {
        guard isTerminalFrontmost, let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func setFrontmost(bundleIdentifier: String?) {
        let isTerminal = bundleIdentifier.map(Self.terminalBundleIdentifiers.contains) ?? false
        guard isTerminal != isTerminalFrontmost else { return }
        isTerminalFrontmost = isTerminal
        if !isTerminal { flushWord() }
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: isTerminal) }
    }

    private func handle(event: CGEvent) {
        guard let nsEvent = NSEvent(cgEvent: event) else { return }
        if nsEvent.keyCode == Self.deleteKeyCode {
            // A pending (uncomposed) syllable takes the backspace first,
            // same as any real IME — only once there's nothing left
            // in-progress does it fall back to erasing a finalized character.
            if composer.hasPending {
                composer.backspace()
            } else if !wordBuffer.isEmpty {
                wordBuffer.removeLast()
            }
            return
        }
        guard let characters = nsEvent.characters else { return }
        for ch in characters {
            if HangulComposer.isJamo(ch) {
                wordBuffer += composer.ingest(ch)
            } else if ch.isLetter || ch.isNumber {
                wordBuffer += composer.flush()
                wordBuffer.append(ch)
            } else {
                wordBuffer += composer.flush()
                flushWord()
            }
        }
    }

    private func flushWord() {
        wordBuffer += composer.flush()
        guard !wordBuffer.isEmpty else { return }
        onWord(wordBuffer)
        wordBuffer = ""
    }
}
