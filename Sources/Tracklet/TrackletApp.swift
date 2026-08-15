import SwiftUI

@main
struct TrackletApp: App {
    @StateObject private var model = SettingsViewModel(
        preferencesStore: UserDefaultsPreferencesStore(),
        authService: SpotifyAuthService(configuration: .current, credentialStore: KeychainCredentialStore()),
        apiClient: nil
    )

    var body: some Scene {
        WindowGroup {
            SettingsView(model: model)
                .frame(width: 430, height: 760)
                .task { await model.restoreSession() }
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)
    }
}
