import ApplicationServices
import Combine

/// Tracks whether the app is trusted for Accessibility, and drives the
/// system permission prompt. macOS has no change notification for trust
/// status, so this polls continuously for the app's whole lifetime — not
/// just while waiting for the user to grant it during onboarding, but for
/// as long as the app runs, so revoking it later in System Settings is
/// noticed too instead of tracking just going silently dead.
final class AccessibilityGate: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()
    private var timer: Timer?

    init() {
        startPolling()
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.isTrusted = AXIsProcessTrusted()
        }
    }
}
