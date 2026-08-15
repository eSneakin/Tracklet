import Foundation

struct SpotifyUser: Decodable {
    let displayName: String?
    let images: [SpotifyImage]

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case images
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        // ponytail: Spotify omits images for accounts without profile artwork; empty list keeps profile usable.
        images = try container.decodeIfPresent([SpotifyImage].self, forKey: .images) ?? []
    }
}

struct SpotifyImage: Decodable {
    let url: URL
}
