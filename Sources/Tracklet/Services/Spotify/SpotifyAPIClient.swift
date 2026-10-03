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
            if let retryAfter, retryAfter.isFinite, retryAfter >= 0 { "Spotify rate limit. Try again in \(Int(min(retryAfter.rounded(.up), 86_400))) seconds." }
            else { "Spotify rate limit reached. Try again shortly." }
        case .decodingFailed: "Spotify response could not be read."
        }
    }
}

@MainActor
final class SpotifyAPIClient {
    private static let baseURL = "https://api.spotify.com/v1"
    private let authService: SpotifyAuthService
    private let session: URLSession
    private var retryDate = Date.distantPast

    init(authService: SpotifyAuthService, session: URLSession = .shared) {
        self.authService = authService
        self.session = session
    }

    func currentUser() async throws -> SpotifyUser {
        guard let user: SpotifyUser = try await get("/me") else {
            throw SpotifyAPIError.invalidResponse
        }
        return user
    }

    func getPlaybackState() async throws -> SpotifyPlaybackDTO? {
        try await get("/me/player?additional_types=track,episode", allowNoContent: true)
    }

    func getCurrentlyPlaying() async throws -> SpotifyPlaybackDTO? {
        try await get("/me/player/currently-playing?additional_types=track,episode", allowNoContent: true)
    }

    func sendPlaybackCommand(method: String, path: String, queryItems: [URLQueryItem] = [], body: Data? = nil) async throws {
        var components = URLComponents(string: "\(Self.baseURL)\(path)")
        if !queryItems.isEmpty { components?.queryItems = queryItems }
        guard let url = components?.url else {
            throw SpotifyAPIError.invalidResponse
        }
        _ = try await request(url, method: method, body: body)
    }

    private func get<T: Decodable>(_ path: String, allowNoContent: Bool = false) async throws -> T? {
        guard let url = URL(string: "\(Self.baseURL)\(path)") else { throw SpotifyAPIError.invalidResponse }
        let (data, http) = try await request(url)
        if http.statusCode == 204, allowNoContent { return nil }
        guard let value = try? JSONDecoder().decode(T.self, from: data) else { throw SpotifyAPIError.decodingFailed }
        return value
    }

    /// Reads and commands share one refresh retry and one server-imposed cooldown.
    private func request(_ url: URL, method: String = "GET", body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        try checkRateLimit()
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        var token = try await authService.validAccessToken()
        for attempt in 0...1 {
            try Task.checkCancellation()
            try checkRateLimit()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SpotifyAPIError.invalidResponse }
            if http.statusCode == 401, attempt == 0 {
                token = try await authService.refreshAccessToken(rejectedToken: token)
            } else {
                try validate(http)
                return (data, http)
            }
        }
        throw SpotifyAPIError.unauthorized
    }

    private func checkRateLimit() throws {
        let remaining = retryDate.timeIntervalSinceNow
        if remaining > 0 { throw SpotifyAPIError.rateLimited(remaining) }
    }

    private func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300: return
        case 401: throw SpotifyAPIError.unauthorized
        case 403: throw SpotifyAPIError.forbidden
        case 404: throw SpotifyAPIError.notFound
        case 429:
            let header = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            let delay = header.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? 30
            retryDate = max(retryDate, Date().addingTimeInterval(max(1, delay)))
            throw SpotifyAPIError.rateLimited(delay)
        default: throw SpotifyAPIError.httpStatus(response.statusCode)
        }
    }
}
