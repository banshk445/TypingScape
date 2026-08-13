import ApplicationServices
import Combine

/// Tracks whether the app is trusted for Accessibility, and drives the
/// system permission prompt. macOS has no change notification for trust
/// status, so we poll while waiting for the user to flip it in Settings.
final class AccessibilityGate: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()
    private var timer: Timer?

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        startPolling()
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.isTrusted = AXIsProcessTrusted()
            if self.isTrusted { self.timer?.invalidate() }
        }
    }
}
