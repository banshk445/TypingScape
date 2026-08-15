import AppKit
import SwiftUI

/// SwiftUI's `Window(id:)` persists its frame across launches, keyed to
/// that id — useful normally, but during dev (`dev-run.sh` relaunching
/// often, screen setups changing) that saved frame can drift to where the
/// title bar/traffic lights sit above the current screen's visible area,
/// making the window look "cut off" at the top with no way to drag it back
/// up into reach. Clamping the frame into the current screen's visible
/// bounds right after the window appears fixes that without touching
/// anything the user does afterward — they can still move/resize freely.
struct WindowPositionFixer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window, let screen = window.screen ?? NSScreen.main else { return }
            let visible = screen.visibleFrame
            var frame = window.frame
            if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }
            if frame.minY < visible.minY { frame.origin.y = visible.minY }
            if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width }
            if frame.minX < visible.minX { frame.origin.x = visible.minX }
            if frame != window.frame { window.setFrame(frame, display: true) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
