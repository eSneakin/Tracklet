import AppIntents

extension PlaybackAction: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Playback action" }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [.previous: "Previous", .play: "Play", .pause: "Pause", .next: "Next",
         .repeatTrack: "Repeat song", .repeatOff: "Turn repeat off"]
    }
}

@available(macOS 14.0, *)
struct WidgetPlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource { "Control Tracklet playback" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Action") var action: PlaybackAction

    #if !WIDGET_EXTENSION
    @Dependency private var runtime: TrackletRuntime
    #endif

    init() {}
    init(action: PlaybackAction) { self.action = action }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        // AudioPlaybackIntent runs in the host app: reuse its session and action gate.
        await runtime.start()
        await runtime.playback.performWidgetAction(action)
        #else
        // Defensive fallback if the system has stale app-intent registration after an update.
        if let store = WidgetSharedStore.configured(), var snapshot = try? store.read() {
            snapshot.interaction = .failed("Open Tracklet and try again.")
            try? store.write(snapshot)
        }
        #endif
        return .result()
    }
}
