import AppKit
import SwiftUI

/// SwiftUI's `Window(id:)` persists its frame across launches, keyed to
/// that id — useful normally, but on a multi-display setup (this machine
/// has three: a 1920×1080 external, a Retina built-in, and an iPad used
/// as a Sidecar display) a saved frame from a since-changed arrangement
/// can land the window where the title bar/traffic lights are outside
/// every currently-connected screen's bounds, with no way to drag it back
/// into reach. A one-shot clamp against `window.screen` wasn't enough —
/// on this setup either the restore lands after that single check runs,
/// or the window doesn't overlap any current screen so `.screen` can't
/// tell where it visually ended up. `center()` sidesteps guessing which
/// screen entirely (AppKit resolves that itself), and running it at three
/// points over the first second gives it a chance to win against however
/// late the OS applies its own restored frame.
struct WindowPositionFixer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        for delay in [0.0, 0.3, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                view.window?.center()
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
