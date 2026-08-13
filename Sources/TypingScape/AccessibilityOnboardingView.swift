import SwiftUI

struct AccessibilityOnboardingView: View {
    @ObservedObject var gate: AccessibilityGate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("손쉬운 사용 권한이 필요해요")
                .font(Theme.serif(15, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("오늘 입력한 단어를 세려면 시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 TypingScape를 허용해주세요.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSecondary)
            Button("권한 요청") { gate.requestPermission() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .frame(width: 300)
    }
}
