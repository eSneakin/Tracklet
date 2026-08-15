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
        }
    }
}

@MainActor
final class SpotifyAuthService {
    private let configuration: SpotifyConfiguration
    private let credentialStore: CredentialStore
    private var session: SpotifySession?
    private var browserSession: ASWebAuthenticationSession?
    private var presentationContextProvider: AuthenticationPresentationContextProvider?

    init(configuration: SpotifyConfiguration, credentialStore: CredentialStore) {
        self.configuration = configuration
        self.credentialStore = credentialStore
    }

    func restoreSession() throws -> SpotifySession? {
        session = try credentialStore.readSession()
        return session
    }

    func authorize() async throws -> SpotifySession {
        guard !configuration.clientID.isEmpty else { throw SpotifyAuthError.configurationMissing }
        let verifier = try Self.randomString(length: 64)
        let state = try Self.randomString(length: 32)
        let challenge = Self.codeChallenge(for: verifier)
        let callback = try await openAuthorizationURL(challenge: challenge, state: state)
        guard let returnedState = callback.queryItem("state"), returnedState == state else {
            throw SpotifyAuthError.stateMismatch
        }
        if let reason = callback.queryItem("error") {
            throw reason == "access_denied" ? SpotifyAuthError.userCancelled : .authorizationFailed(reason)
        }
        guard let code = callback.queryItem("code") else { throw SpotifyAuthError.invalidCallback }
        let newSession = try await exchange(code: code, verifier: verifier)
        try credentialStore.save(newSession)
        session = newSession
        return newSession
    }

    func validAccessToken() async throws -> String {
        let current: SpotifySession?
        if let session {
            current = session
        } else {
            current = try credentialStore.readSession()
        }
        guard let current else {
            throw SpotifyAuthError.noSession
        }
        if !current.needsRefresh {
            session = current
            return current.accessToken
        }
        let refreshed = try await refresh(current)
        try credentialStore.save(refreshed)
        session = refreshed
        return refreshed.accessToken
    }

    func disconnect() throws {
        session = nil
        try credentialStore.deleteSession()
    }

    private func openAuthorizationURL(challenge: String, state: String) async throws -> URL {
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge)
        ]
        guard let url = components.url else { throw SpotifyAuthError.invalidCallback }
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: configuration.redirectURI.scheme
            ) { callback, error in
                if let error {
                    let nsError = error as NSError
                    continuation.resume(throwing: nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
                        ? SpotifyAuthError.userCancelled : error)
                } else if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: SpotifyAuthError.invalidCallback)
                }
            }
            let provider = AuthenticationPresentationContextProvider()
            presentationContextProvider = provider
            session.presentationContextProvider = provider
            session.prefersEphemeralWebBrowserSession = false
            browserSession = session
            session.start()
        }
    }

    private func exchange(code: String, verifier: String) async throws -> SpotifySession {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormEncoder.encode([
            "client_id": configuration.clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": configuration.redirectURI.absoluteString,
            "code_verifier": verifier
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SpotifyAuthError.tokenExchangeFailed
        }
        let token = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        return SpotifySession(accessToken: token.accessToken, refreshToken: token.refreshToken ?? "", expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn)), scope: token.scope)
    }

    private func refresh(_ current: SpotifySession) async throws -> SpotifySession {
        guard !current.refreshToken.isEmpty else { throw SpotifyAuthError.refreshFailed }
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormEncoder.encode([
            "client_id": configuration.clientID,
            "grant_type": "refresh_token",
            "refresh_token": current.refreshToken
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let token = try? JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        else { throw SpotifyAuthError.refreshFailed }
        return SpotifySession(accessToken: token.accessToken, refreshToken: token.refreshToken ?? current.refreshToken, expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn)), scope: token.scope.isEmpty ? current.scope : token.scope)
    }

    private static func randomString(length: Int) throws -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
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
        values.map { "\($0.key)=\($0.value.formURLEncoded)" }.joined(separator: "&").data(using: .utf8)!
    }
}

private extension String {
    var formURLEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))) ?? self
    }
}

private extension URL {
    func queryItem(_ name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
}
