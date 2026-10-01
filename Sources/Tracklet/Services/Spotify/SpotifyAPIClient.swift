import Foundation

enum SpotifyAPIError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case unauthorized
    case forbidden
    case notFound
    case rateLimited(TimeInterval?)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Spotify returned an invalid response."
        case .httpStatus(let status): "Spotify request failed (\(status))."
        case .unauthorized: "Spotify session is no longer authorized."
        case .forbidden: "Spotify refused playback control. Check Spotify Premium and playback permissions."
        case .notFound: "Open Spotify to continue. No active playback device found."
        case .rateLimited(let retryAfter):
            if let retryAfter { "Spotify rate limit. Try again in \(Int(retryAfter)) seconds." }
            else { "Spotify rate limit reached. Try again shortly." }
        case .decodingFailed: "Spotify response could not be read."
        }
    }
}

@MainActor
final class SpotifyAPIClient {
    private let authService: SpotifyAuthService
    private let session: URLSession

    init(authService: SpotifyAuthService, session: URLSession = .shared) {
        self.authService = authService
        self.session = session
    }

    func currentUser() async throws -> SpotifyUser {
        guard let user: SpotifyUser = try await get("https://api.spotify.com/v1/me") else {
            throw SpotifyAPIError.invalidResponse
        }
        return user
    }

    func getPlaybackState() async throws -> SpotifyPlaybackDTO? {
        try await get("https://api.spotify.com/v1/me/player", allowNoContent: true)
    }

    func getCurrentlyPlaying() async throws -> SpotifyCurrentlyPlayingDTO? {
        try await get("https://api.spotify.com/v1/me/player/currently-playing?additional_types=track,episode", allowNoContent: true)
    }

    func sendPlaybackCommand(method: String, path: String, queryItems: [URLQueryItem] = [], body: Data? = nil) async throws {
        var components = URLComponents(string: "https://api.spotify.com/v1\(path)")
        if !queryItems.isEmpty { components?.queryItems = queryItems }
        guard let url = components?.url else {
            throw SpotifyAPIError.invalidResponse
        }
        var token = try await authService.validAccessToken()
        var response = try await commandRequest(url, method: method, token: token, body: body)
        if response.statusCode == 401 {
            token = try await authService.refreshAccessToken()
            response = try await commandRequest(url, method: method, token: token, body: body)
        }
        try validate(response)
    }

    private func get<T: Decodable>(_ urlString: String, allowNoContent: Bool = false) async throws -> T? {
        guard let url = URL(string: urlString) else { throw SpotifyAPIError.invalidResponse }
        var token = try await authService.validAccessToken()
        var (data, response) = try await request(url, token: token)

        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            token = try await authService.refreshAccessToken()
            (data, response) = try await request(url, token: token)
        }

        guard let http = response as? HTTPURLResponse else { throw SpotifyAPIError.invalidResponse }
        if http.statusCode == 204, allowNoContent { return nil }
        try validate(http)
        guard let value = try? JSONDecoder().decode(T.self, from: data) else { throw SpotifyAPIError.decodingFailed }
        return value
    }

    private func request(_ url: URL, token: String) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await session.data(for: request)
    }

    private func commandRequest(_ url: URL, method: String, token: String, body: Data?) async throws -> HTTPURLResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw SpotifyAPIError.invalidResponse }
        return response
    }

    private func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300: return
        case 401: throw SpotifyAPIError.unauthorized
        case 403: throw SpotifyAPIError.forbidden
        case 404: throw SpotifyAPIError.notFound
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw SpotifyAPIError.rateLimited(retryAfter)
        default: throw SpotifyAPIError.httpStatus(response.statusCode)
        }
    }
}
