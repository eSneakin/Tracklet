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
    private var authenticationAttempt = UUID()
    private var connectionTask: Task<Void, Never>?

    init(preferencesStore: PreferencesStore, authService: SpotifyAuthService, apiClient: SpotifyAPIClient? = nil) {
        self.preferencesStore = preferencesStore
        self.authService = authService
        self.apiClient = apiClient ?? SpotifyAPIClient(authService: authService)
        preferences = preferencesStore.load()
    }

    func connectSpotify() {
        guard !isConnecting else { return }
        authenticationAttempt = UUID()
        let attempt = authenticationAttempt
        authenticationState = .connecting
        connectionTask = Task {
            await authenticate(restoring: false, attempt: attempt)
        }
    }

    func disconnectSpotify() {
        authenticationAttempt = UUID()
        connectionTask?.cancel()
        connectionTask = nil
        do {
            try authService.disconnect()
            authenticationState = .disconnected
        } catch {
            authenticationState = .error(error.localizedDescription)
        }
    }

    func restoreSession() async {
        guard !isConnecting, account == nil else { return }
        authenticationAttempt = UUID()
        authenticationState = .connecting
        await authenticate(restoring: true, attempt: authenticationAttempt)
    }

    private func authenticate(restoring: Bool, attempt: UUID) async {
        // Check both sides of suspension: Disconnect may run before this task even starts.
        guard authenticationAttempt == attempt, !Task.isCancelled else { return }
        do {
            if restoring {
                guard try authService.restoreSession() != nil else {
                    authenticationState = .disconnected
                    return
                }
            } else {
                _ = try await authService.authorize()
            }
            guard authenticationAttempt == attempt else { return }
            try Task.checkCancellation()
            let user = try await apiClient.currentUser()
            guard authenticationAttempt == attempt else { return }
            try Task.checkCancellation()
            authenticationState = .connected(SpotifyAccount(user: user))
        } catch {
            guard authenticationAttempt == attempt else { return }
            // Only explicit Disconnect removes credentials; offline/profile failures remain retryable.
            authenticationState = .error(error.localizedDescription)
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
