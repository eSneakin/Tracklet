import AuthenticationServices
import CryptoKit
import Foundation
import Security

enum SpotifyAuthError: LocalizedError {
    case configurationMissing
    case invalidCallback
    case stateMismatch
    case userCancelled
    case authorizationFailed(String)
    case tokenExchangeFailed
    case noSession
    case refreshFailed
    case tokenRequestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .configurationMissing: "Add Spotify Client ID and Redirect URI."
        case .invalidCallback: "Spotify callback was invalid."
        case .stateMismatch: "Spotify login state did not match."
        case .userCancelled: "Spotify login cancelled."
        case .authorizationFailed(let reason): "Spotify authorization failed: \(reason)."
        case .tokenExchangeFailed: "Could not exchange Spotify authorization code."
        case .noSession: "No Spotify session found."
        case .refreshFailed: "Spotify session expired. Connect again."
        case .tokenRequestFailed(let status): "Spotify token request failed (\(status)). Try again."
        }
    }
}

@MainActor
final class SpotifyAuthService {
    private let configuration: SpotifyConfiguration
    private let credentialStore: CredentialStore
    private let urlSession: URLSession
    private let authorizationHandler: ((URL) async throws -> URL)?
    private var session: SpotifySession?
    private var didLoadSession = false
    private var generation = UUID()
    private var refreshTask: Task<SpotifySession, Error>?
    private var browserSession: ASWebAuthenticationSession?
    private var presentationContextProvider: AuthenticationPresentationContextProvider?
    private var authorizationContinuation: CheckedContinuation<URL, Error>?

    init(configuration: SpotifyConfiguration, credentialStore: CredentialStore,
         urlSession: URLSession = .shared, authorizationHandler: ((URL) async throws -> URL)? = nil) {
        self.configuration = configuration
        self.credentialStore = credentialStore
        self.urlSession = urlSession
        self.authorizationHandler = authorizationHandler
    }

    func restoreSession() throws -> SpotifySession? {
        if !didLoadSession {
            session = try credentialStore.readSession()
            didLoadSession = true
        }
        return session
    }

    func authorize() async throws -> SpotifySession {
        try Task.checkCancellation()
        guard !configuration.clientID.isEmpty else { throw SpotifyAuthError.configurationMissing }
        invalidatePendingWork()
        let generation = generation
        return try await withTaskCancellationHandler {
            let verifier = try Self.randomString(length: 64)
            let state = try Self.randomString(length: 32)
            let callback = try await openAuthorizationURL(challenge: Self.codeChallenge(for: verifier), state: state)
            try checkGeneration(generation)
            guard callback.scheme == configuration.redirectURI.scheme,
                  callback.host == configuration.redirectURI.host,
                  callback.port == configuration.redirectURI.port,
                  callback.path == configuration.redirectURI.path else { throw SpotifyAuthError.invalidCallback }
            guard callback.queryItem("state") == state else { throw SpotifyAuthError.stateMismatch }
            if let reason = callback.queryItem("error") {
                throw reason == "access_denied" ? SpotifyAuthError.userCancelled : .authorizationFailed(reason)
            }
            guard let code = callback.queryItem("code"), !code.isEmpty else { throw SpotifyAuthError.invalidCallback }
            let newSession = try await requestToken([
                "grant_type": "authorization_code", "code": code,
                "redirect_uri": configuration.redirectURI.absoluteString, "code_verifier": verifier
            ])
            try checkGeneration(generation)
            try credentialStore.save(newSession)
            session = newSession
            didLoadSession = true
            // A refresh started during login must not overwrite the newly selected account.
            invalidatePendingWork()
            return newSession
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                self.invalidatePendingWork()
            }
        }
    }

    func validAccessToken() async throws -> String {
        try await accessToken(forceRefresh: false)
    }

    func disconnect() throws {
        invalidatePendingWork()
        session = nil
        // Even if deletion fails, this process must not reload the disconnected credentials.
        didLoadSession = true
        try credentialStore.deleteSession()
    }

    func refreshAccessToken(rejectedToken: String? = nil) async throws -> String {
        try await accessToken(forceRefresh: true, rejectedToken: rejectedToken)
    }

    private func accessToken(forceRefresh: Bool, rejectedToken: String? = nil) async throws -> String {
        try Task.checkCancellation()
        guard let current = try restoreSession() else { throw SpotifyAuthError.noSession }
        let generation = generation
        let task: Task<SpotifySession, Error>
        if let refreshTask {
            task = refreshTask
        } else {
            // A delayed 401 may refer to a token another request has already replaced.
            if !current.needsRefresh, !forceRefresh || (rejectedToken != nil && rejectedToken != current.accessToken) {
                return current.accessToken
            }
            task = Task {
                defer { if self.generation == generation { self.refreshTask = nil } }
                guard !current.refreshToken.isEmpty else { throw SpotifyAuthError.refreshFailed }
                let refreshed = try await self.requestToken([
                    "grant_type": "refresh_token", "refresh_token": current.refreshToken
                ], refreshing: current)
                try self.checkGeneration(generation)
                try self.credentialStore.save(refreshed)
                self.session = refreshed
                return refreshed
            }
            refreshTask = task
        }
        // Waiters share the refresh and its persistence; cancelling one waiter leaves the others running.
        let refreshed = try await task.value
        try checkGeneration(generation)
        return refreshed.accessToken
    }

    private func checkGeneration(_ expected: UUID) throws {
        try Task.checkCancellation()
        guard generation == expected else { throw CancellationError() }
    }

    private func invalidatePendingWork() {
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        browserSession?.cancel()
        finishAuthorization(.failure(CancellationError()))
    }

    private func finishAuthorization(_ result: Result<URL, Error>) {
        let continuation = authorizationContinuation
        authorizationContinuation = nil
        browserSession = nil
        presentationContextProvider = nil
        continuation?.resume(with: result)
    }

    private func openAuthorizationURL(challenge: String, state: String) async throws -> URL {
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: SpotifyConfiguration.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge)
        ]
        guard let url = components.url else { throw SpotifyAuthError.invalidCallback }
        if let authorizationHandler { return try await authorizationHandler(url) }
        try Task.checkCancellation()
        let generation = generation
        return try await withCheckedThrowingContinuation { continuation in
            authorizationContinuation = continuation
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: configuration.redirectURI.scheme
            ) { [weak self] callback, error in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == generation else { return }
                    if let error {
                        let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                        self.finishAuthorization(.failure(cancelled ? SpotifyAuthError.userCancelled : error))
                    } else if let callback {
                        self.finishAuthorization(.success(callback))
                    } else {
                        self.finishAuthorization(.failure(SpotifyAuthError.invalidCallback))
                    }
                }
            }
            let provider = AuthenticationPresentationContextProvider()
            presentationContextProvider = provider
            session.presentationContextProvider = provider
            session.prefersEphemeralWebBrowserSession = false
            browserSession = session
            if !session.start() {
                finishAuthorization(.failure(SpotifyAuthError.authorizationFailed("Could not open the login window")))
            }
        }
    }

    private func requestToken(_ values: [String: String], refreshing current: SpotifySession? = nil) async throws -> SpotifySession {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormEncoder.encode(values.merging(["client_id": configuration.clientID]) { _, clientID in clientID })
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SpotifyAuthError.tokenExchangeFailed }
        guard http.statusCode == 200 else {
            struct TokenError: Decodable { let error: String }
            let reason = try? JSONDecoder().decode(TokenError.self, from: data)
            if current != nil, http.statusCode == 400, reason?.error == "invalid_grant" {
                throw SpotifyAuthError.refreshFailed
            }
            throw SpotifyAuthError.tokenRequestFailed(http.statusCode)
        }
        let token = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        guard let refreshToken = token.refreshToken ?? current?.refreshToken, !refreshToken.isEmpty else {
            throw SpotifyAuthError.tokenExchangeFailed
        }
        return SpotifySession(accessToken: token.accessToken, refreshToken: refreshToken,
                              expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn)),
                              scope: token.scope.isEmpty ? current?.scope ?? "" : token.scope)
    }

    private static func randomString(length: Int) throws -> String {
        // A 64-character alphabet divides the byte range evenly, avoiding modulo bias.
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        var bytes = [UInt8](repeating: 0, count: length)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw SpotifyAuthError.invalidCallback }
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    private static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private final class AuthenticationPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.windows.first ?? NSApplication.shared.mainWindow ?? NSWindow()
    }
}

private enum FormEncoder {
    static func encode(_ values: [String: String]) -> Data {
        Data(values.map { "\($0.key.formURLEncoded)=\($0.value.formURLEncoded)" }.joined(separator: "&").utf8)
    }
}

private extension String {
    var formURLEncoded: String {
        addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"))!
    }
}

private extension URL {
    func queryItem(_ name: String) -> String? {
        let matches = URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems?.filter { $0.name == name }
        return matches?.count == 1 ? matches?.first?.value : nil
    }
}
