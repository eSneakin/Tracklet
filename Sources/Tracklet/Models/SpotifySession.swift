import Foundation

struct SpotifySession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let scope: String

    var needsRefresh: Bool {
        expiresAt <= Date().addingTimeInterval(60)
    }
}

struct SpotifyTokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        tokenType = try container.decode(String.self, forKey: .tokenType)
        expiresIn = try container.decode(Int.self, forKey: .expiresIn)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        scope = try container.decodeIfPresent(String.self, forKey: .scope) ?? ""
    }
}
