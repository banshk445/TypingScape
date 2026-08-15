import SwiftUI

/// Unlike `AccessibilityOnboardingView`, this doesn't block anything —
/// the app works fully without this permission, just missing terminal
/// words — so it's a small dismissible-feeling hint, not a gate screen.
struct InputMonitoringHintView: View {
    @ObservedObject var gate: InputMonitoringGate

    var body: some View {
        HStack(spacing: 8) {
            Text("터미널에서 입력한 단어도 세려면")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkSecondary)
            Button("권한 허용") { gate.requestPermission() }
                .buttonStyle(QuietButtonStyle())
        }
    }
}
