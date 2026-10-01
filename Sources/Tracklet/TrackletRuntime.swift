import Foundation

/// One composition root, shared by the window and background App Intents.
@MainActor
final class TrackletRuntime: ObservableObject {
    let settings: SettingsViewModel
    let playback: PlaybackViewModel
    private let publisher: WidgetSnapshotPublisher
    private var startup: Task<Void, Never>?

    init() {
        let auth = SpotifyAuthService(configuration: .current, credentialStore: KeychainCredentialStore())
        let client = SpotifyAPIClient(authService: auth)
        let publisher = WidgetSnapshotPublisher(store: .configured())
        self.publisher = publisher
        settings = SettingsViewModel(
            preferencesStore: UserDefaultsPreferencesStore(legacyDefaults: UserDefaults(suiteName: "Tracklet")),
            authService: auth, apiClient: client
        )
        playback = PlaybackViewModel(service: SpotifyPlaybackService(apiClient: client),
                                     onPlaybackUpdate: publisher.publish, onPlaybackFailure: publisher.publishFailure,
                                     artworkLookup: publisher.cachedArtworkURL)
    }

    func start() async {
        if let startup { await startup.value; return }
        let task = Task {
            await settings.restoreSession()
            publisher.start(settings: settings, playback: playback)
            await playback.startPolling()
        }
        startup = task
        await task.value
    }
}
