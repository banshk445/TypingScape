import AppKit
import ApplicationServices

/// Terminal emulators render their buffer as a custom character grid
/// instead of exposing it through a normal text field's Accessibility
/// value the way `FocusedTextTracker` reads — and even where an AX value
/// exists, it's the whole visible screen (prompt, command output, scrollback)
/// with no way to tell what the user actually typed from what a program
/// printed. A raw keystroke tap is the only signal that's actually theirs.
///
/// ponytail: unlike `FocusedTextTracker`, this sees keys before IME
/// composition — a 2-beolsik Hangul input produces one raw jamo per
/// keystroke here, not the composed syllable, so Korean terminal input
/// segments less accurately. Accepted trade-off for terminal coverage at
/// all (README-documented limitation lifted only for ASCII-ish accuracy).
///
/// ponytail: sees every keystroke while a terminal is frontmost, including
/// anything typed at a `sudo`/`ssh` password prompt. `WordStore.record`'s
/// existing spell-check filter is the only backstop — a password that
/// happens to be a real dictionary word isn't caught. Accepted trade-off
/// (user confirmed); revisit with a pause-after-sudo/ssh heuristic if it
/// turns out to matter.
final class TerminalKeyTracker {
    /// Not exhaustive — extend as new terminal apps come up.
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
    ]
    private static let deleteKeyCode: UInt16 = 51

    private let onWord: (String) -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activationToken: NSObjectProtocol?
    private var wordBuffer = ""
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
            callback: { _, _, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                Unmanaged<TerminalKeyTracker>.fromOpaque(refcon).takeUnretainedValue().handle(event: event)
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
            if !wordBuffer.isEmpty { wordBuffer.removeLast() }
            return
        }
        guard let characters = nsEvent.characters else { return }
        for ch in characters {
            if ch.isLetter || ch.isNumber {
                wordBuffer.append(ch)
            } else {
                flushWord()
            }
        }
    }

    private func flushWord() {
        guard !wordBuffer.isEmpty else { return }
        onWord(wordBuffer)
        wordBuffer = ""
    }
}
