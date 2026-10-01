import AppKit
import AppIntents
import SwiftUI

@main
struct TrackletApp: App {
    @NSApplicationDelegateAdaptor(TrackletApplicationDelegate.self) private var applicationDelegate
    @StateObject private var runtime: TrackletRuntime

    init() {
        let runtime = TrackletRuntime()
        _runtime = StateObject(wrappedValue: runtime)
        AppDependencyManager.shared.add(dependency: runtime)
    }

    var body: some Scene {
        WindowGroup {
            SettingsView(model: runtime.settings, playbackModel: runtime.playback)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task {
                    await runtime.start()
                }
        }
        .defaultSize(width: 520, height: 760)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
    }
}

@MainActor
final class TrackletApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // `swift run` launches an unbundled executable with a prohibited activation policy.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        assert(NSApplication.shared.activationPolicy() == .regular)
        // Bundled launches are activated by macOS; background widget actions must not steal focus.
        guard Bundle.main.bundleIdentifier == nil else { return }
        if #available(macOS 14.0, *) {
            NSApplication.shared.activate()
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
