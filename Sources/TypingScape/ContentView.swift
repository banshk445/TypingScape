import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var wordStore: WordStore
    @ObservedObject var accessibilityGate: AccessibilityGate
    @ObservedObject var inputMonitoringGate: InputMonitoringGate
    @ObservedObject var maskStore: MaskStore
    @ObservedObject var styleStore: StyleStore
    @Environment(\.openWindow) private var openWindow

    private static let previewSize = CGSize(width: 316, height: 190)
    /// `MountainWordCloud`'s font sizes are absolute (8–15pt), so drawing
    /// it straight into this small frame made the text enormous relative to
    /// the shape — the popover and the big window showed visibly different
    /// pictures of the same data. Rendering at the big window's own width
    /// and scaling the whole thing down instead keeps the text-to-shape
    /// ratio identical, so the popover reads as a true miniature of what
    /// "크게 보기" opens.
    private static let referenceWidth = BigMountainView.canvasMinWidth
    private static var previewScale: CGFloat { previewSize.width / referenceWidth }
    private static var referenceSize: CGSize {
        CGSize(width: referenceWidth, height: previewSize.height / previewScale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !accessibilityGate.isTrusted {
                AccessibilityOnboardingView(gate: accessibilityGate)
            } else {
                // Same word budget as the big window, for the same reason:
                // a miniature of a different set of words isn't a preview.
                MountainWordCloud(topWords: Array(wordStore.topWords.prefix(BigMountainView.wordBudget)), mask: maskStore.mask, style: styleStore.wordCloudStyle, swellOffset: maskStore.swellOffset)
                    .frame(width: Self.referenceSize.width, height: Self.referenceSize.height)
                    .scaleEffect(Self.previewScale)
                    .frame(width: Self.previewSize.width, height: Self.previewSize.height)
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
