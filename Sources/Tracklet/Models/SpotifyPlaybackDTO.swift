import Foundation

struct SpotifyPlaybackDTO: Decodable {
    let isPlaying: Bool
    let progressMS: Int?
    let item: SpotifyPlayableItem?
    let device: SpotifyDeviceDTO?
    let repeatState: String?

    enum CodingKeys: String, CodingKey {
        case isPlaying = "is_playing"
        case progressMS = "progress_ms"
        case item
        case device
        case repeatState = "repeat_state"
    }
}

enum SpotifyPlayableItem: Decodable {
    case track(SpotifyTrackDTO)
    case episode(SpotifyEpisodeDTO)
    case unknown(SpotifyUnknownItemDTO)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type)
        switch type {
        case "track": self = .track(try SpotifyTrackDTO(from: decoder))
        case "episode": self = .episode(try SpotifyEpisodeDTO(from: decoder))
        default: self = .unknown(try SpotifyUnknownItemDTO(from: decoder))
        }
    }

    private enum TypeKey: String, CodingKey { case type }
}

struct SpotifyTrackDTO: Decodable {
    let id: String?
    let uri: String?
    let name: String
    let durationMS: Int
    let artists: [SpotifyArtistDTO]
    let album: SpotifyCollectionDTO?

    enum CodingKeys: String, CodingKey {
        case id, uri, name, artists, album
        case durationMS = "duration_ms"
    }
}

struct SpotifyEpisodeDTO: Decodable {
    let id: String?
    let name: String
    let durationMS: Int
    let show: SpotifyCollectionDTO?
    let images: [SpotifyImage]?

    enum CodingKeys: String, CodingKey {
        case id, name, show, images
        case durationMS = "duration_ms"
    }
}

struct SpotifyUnknownItemDTO: Decodable {
    let id: String?
    let name: String?

    enum CodingKeys: String, CodingKey { case id, name }
}

struct SpotifyArtistDTO: Decodable { let name: String }

/// Albums and podcast shows share the metadata we consume. Keep Spotify-specific
/// decoding here; the service maps this payload into the app's playback model.
struct SpotifyCollectionDTO: Decodable {
    let name: String
    let images: [SpotifyImage]

    enum CodingKeys: String, CodingKey { case name, images }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        images = try container.decodeIfPresent([SpotifyImage].self, forKey: .images) ?? []
    }
}

struct SpotifyDeviceDTO: Decodable {
    let name: String
    let type: String?
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case name, type
        case isActive = "is_active"
    }
}
