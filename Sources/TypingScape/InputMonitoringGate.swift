import Combine
import Foundation
import IOKit.hid

/// Mirrors `AccessibilityGate`, but for the separate "Input Monitoring"
/// permission `TerminalKeyTracker` needs — macOS gates any global keystroke
/// tap behind this, distinct from (and independent of) Accessibility trust.
final class InputMonitoringGate: ObservableObject {
    @Published private(set) var isTrusted = InputMonitoringGate.checkAccess()
    private var timer: Timer?

    init() {
        startPolling()
    }

    func requestPermission() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        isTrusted = Self.checkAccess()
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.isTrusted = Self.checkAccess()
        }
    }

    private static func checkAccess() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }
}
