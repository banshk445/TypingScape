import AppKit
import SwiftUI

@main
struct TypingScapeApp: App {
    @StateObject private var wordStore = WordStore()
    @StateObject private var accessibilityGate = AccessibilityGate()
    @StateObject private var inputMonitoringGate = InputMonitoringGate()
    @StateObject private var maskStore = MaskStore()
    @StateObject private var styleStore = StyleStore()
    @State private var tracker: FocusedTextTracker?
    @State private var terminalTracker: TerminalKeyTracker?

    init() {
        Self.terminateOtherRunningInstances()
    }

    var body: some Scene {
        MenuBarExtra("TypingScape", systemImage: "mountain.2.fill") {
            ContentView(wordStore: wordStore, accessibilityGate: accessibilityGate, inputMonitoringGate: inputMonitoringGate, maskStore: maskStore, styleStore: styleStore)
                .onAppear {
                    startTapIfNeeded()
                    startTerminalTapIfNeeded()
                }
                .onChange(of: accessibilityGate.isTrusted) { _, trusted in
                    if trusted {
                        startTapIfNeeded()
                    } else {
                        // Revoked in System Settings while running — stop
                        // tracking and clear the tracker so a later
                        // re-grant starts a fresh one instead of assuming
                        // the old (now-broken) observer still works.
                        tracker?.stop()
                        tracker = nil
                    }
                }
                .onChange(of: inputMonitoringGate.isTrusted) { _, trusted in
                    if trusted {
                        startTerminalTapIfNeeded()
                    } else {
                        terminalTracker?.stop()
                        terminalTracker = nil
                    }
                }
        }
        .menuBarExtraStyle(.window)

        Window("TypingScape", id: "big-mountain") {
            BigMountainView(wordStore: wordStore, maskStore: maskStore, styleStore: styleStore)
        }
        .defaultSize(width: 1200, height: 850)
        .windowStyle(.hiddenTitleBar)
    }

    private func startTapIfNeeded() {
        guard accessibilityGate.isTrusted, tracker == nil else { return }
        let newTracker = FocusedTextTracker { word in wordStore.record(word: word) }
        newTracker.start()
        tracker = newTracker
    }

    private func startTerminalTapIfNeeded() {
        guard inputMonitoringGate.isTrusted, terminalTracker == nil else { return }
        let newTracker = TerminalKeyTracker { word in wordStore.record(word: word) }
        newTracker.start()
        terminalTracker = newTracker
    }

    /// Dev builds relaunch often (Xcode's ⌘R, `dev-run.sh`) without the old
    /// process ever quitting, which left duplicate menu bar icons each
    /// independently — and pointlessly — asking for Accessibility trust.
    /// Only one instance should ever be alive at a time.
    ///
    /// This bare (non-.app-bundle) executable registers with LaunchServices
    /// with a NULL bundle identifier (confirmed via `lsappinfo list`), so we
    /// match on executable path instead — stable across relaunches from the
    /// same build location.
    private static func terminateOtherRunningInstances() {
        guard let myPath = Bundle.main.executablePath else { return }
        let myPID = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications
        where app.processIdentifier != myPID && app.executableURL?.path == myPath {
            app.forceTerminate()
        }
    }
}
