import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var wordStore: WordStore
    @ObservedObject var accessibilityGate: AccessibilityGate
    @ObservedObject var inputMonitoringGate: InputMonitoringGate
    @ObservedObject var maskStore: MaskStore
    @ObservedObject var styleStore: StyleStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !accessibilityGate.isTrusted {
                AccessibilityOnboardingView(gate: accessibilityGate)
            } else {
                MountainWordCloud(topWords: Array(wordStore.topWords.prefix(30)), mask: maskStore.mask, style: styleStore.wordCloudStyle, swellOffset: maskStore.swellOffset)
                    .frame(width: 316, height: 190)
                    .themedCard()

                Theme.wordCountText(wordStore.wordCounts.count)

                Button("크게 보기") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "big-mountain")
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            // Independent of the accessibility gate above — someone who
            // only wants terminal-word tracking shouldn't have to grant
            // Accessibility first just to see this.
            if !inputMonitoringGate.isTrusted {
                InputMonitoringHintView(gate: inputMonitoringGate)
            }
            Divider().overlay(Theme.border)
            Button("종료") { NSApplication.shared.terminate(nil) }
                .buttonStyle(QuietButtonStyle())
        }
        .padding(14)
        .frame(width: 344)
        .background(ThemedBackground(style: styleStore.backgroundStyle))
        .preferredColorScheme(styleStore.backgroundStyle.colorScheme)
        .onAppear { maskStore.viewDidAppear() }
        .onDisappear { maskStore.viewDidDisappear() }
    }
}
