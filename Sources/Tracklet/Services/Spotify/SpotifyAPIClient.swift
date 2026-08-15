import Foundation

enum SpotifyAPIError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Spotify returned an invalid response."
        case .httpStatus(let status): "Spotify request failed (\(status))."
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
        try await get("https://api.spotify.com/v1/me")
    }

    private func get<T: Decodable>(_ urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else { throw SpotifyAPIError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await authService.validAccessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SpotifyAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw SpotifyAPIError.httpStatus(http.statusCode) }
        guard let value = try? JSONDecoder().decode(T.self, from: data) else { throw SpotifyAPIError.decodingFailed }
        return value
    }
}
