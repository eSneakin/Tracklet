import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var preferences: WidgetPreferences {
        didSet { preferencesStore.save(preferences) }
    }
    @Published private(set) var authenticationState: AuthenticationState = .disconnected

    private let preferencesStore: PreferencesStore
    private let authService: SpotifyAuthService
    private let apiClient: SpotifyAPIClient

    init(preferencesStore: PreferencesStore, authService: SpotifyAuthService, apiClient: SpotifyAPIClient? = nil) {
        self.preferencesStore = preferencesStore
        self.authService = authService
        self.apiClient = apiClient ?? SpotifyAPIClient(authService: authService)
        preferences = preferencesStore.load()
    }

    func connectSpotify() {
        guard !isConnecting else { return }
        authenticationState = .connecting
        Task {
            do {
                _ = try await authService.authorize()
                authenticationState = .connected(SpotifyAccount(user: try await apiClient.currentUser()))
            } catch {
                authenticationState = .error(error.localizedDescription)
            }
        }
    }

    func disconnectSpotify() {
        Task {
            try? authService.disconnect()
            authenticationState = .disconnected
        }
    }

    func restoreSession() async {
        do {
            guard try authService.restoreSession() != nil else { return }
            authenticationState = .connected(SpotifyAccount(user: try await apiClient.currentUser()))
        } catch {
            try? authService.disconnect()
            authenticationState = .disconnected
        }
    }

    var account: SpotifyAccount? {
        guard case .connected(let account) = authenticationState else { return nil }
        return account
    }

    var isConnecting: Bool { if case .connecting = authenticationState { return true }; return false }

    var errorMessage: String? {
        guard case .error(let message) = authenticationState else { return nil }
        return message
    }
}

enum AuthenticationState: Equatable {
    case disconnected
    case connecting
    case connected(SpotifyAccount)
    case error(String)
}
