import Foundation

enum PlaybackServiceError: LocalizedError {
    case missingProgress
    case cannotRestoreItem

    var errorDescription: String? {
        switch self {
        case .missingProgress: "Spotify did not report playback progress. Try again."
        case .cannotRestoreItem: "Open Spotify to choose playback. This saved item cannot be restored."
        }
    }
}

@MainActor
final class SpotifyPlaybackService {
    private let apiClient: SpotifyAPIClient

    init(apiClient: SpotifyAPIClient) { self.apiClient = apiClient }

    func fetchPlaybackState() async throws -> PlaybackState? {
        guard let response = try await apiClient.getPlaybackState() else { return nil }
        return map(response)
    }

    func fetchCurrentlyPlaying() async throws -> PlaybackState? {
        guard let response = try await apiClient.getCurrentlyPlaying() else { return nil }
        return map(response)
    }

    func previous(playback: PlaybackState?) async throws {
        guard let progress = playback?.progressAtFetch, progress.isFinite, progress >= 0 else {
            throw PlaybackServiceError.missingProgress
        }
        // Use the freshly confirmed position, not a widget snapshot or a previous poll.
        if progress >= 3 {
            try await apiClient.sendPlaybackCommand(method: "PUT", path: "/me/player/seek", queryItems: [
                URLQueryItem(name: "position_ms", value: "0")
            ])
        } else {
            try await apiClient.sendPlaybackCommand(method: "POST", path: "/me/player/previous")
        }
    }

    func play() async throws {
        try await apiClient.sendPlaybackCommand(method: "PUT", path: "/me/player/play")
    }

    /// Only used when Spotify confirms an active device with no current item.
    func restore(_ playback: PlaybackState) async throws {
        guard let item = playback.item, item.type == .track, let uri = item.uri,
              uri.hasPrefix("spotify:track:"),
              uri.dropFirst("spotify:track:".count).range(of: "^[A-Za-z0-9]{22}$", options: .regularExpression) != nil
        else { throw PlaybackServiceError.cannotRestoreItem }
        let progress = playback.progress(at: playback.fetchedAt) ?? 0
        guard progress.isFinite, progress >= 0, progress < Double(Int32.max) / 1000 else {
            throw PlaybackServiceError.missingProgress
        }
        struct RestoreRequest: Encodable {
            let uris: [String]
            let position_ms: Int
        }
        let body = try JSONEncoder().encode(RestoreRequest(
            uris: [uri], position_ms: progress >= item.duration ? 0 : Int(progress * 1000)
        ))
        try await apiClient.sendPlaybackCommand(method: "PUT", path: "/me/player/play", body: body)
    }

    func pause() async throws {
        try await apiClient.sendPlaybackCommand(method: "PUT", path: "/me/player/pause")
    }

    func next() async throws {
        try await apiClient.sendPlaybackCommand(method: "POST", path: "/me/player/next")
    }

    func setRepeatMode(_ mode: PlaybackRepeatMode) async throws {
        try await apiClient.sendPlaybackCommand(method: "PUT", path: "/me/player/repeat", queryItems: [
            URLQueryItem(name: "state", value: mode.rawValue)
        ])
    }

    func perform(_ action: PlaybackAction, playback: PlaybackState? = nil) async throws {
        switch action {
        case .previous: try await previous(playback: playback)
        case .play: try await play()
        case .pause: try await pause()
        case .next: try await next()
        case .repeatTrack: try await setRepeatMode(.track)
        case .repeatOff: try await setRepeatMode(.off)
        }
    }

    /// Convert API milliseconds and optional payloads once, before UI or shared storage sees them.
    private func map(_ response: SpotifyPlaybackDTO) -> PlaybackState {
        PlaybackState(
            item: response.item.map(map),
            isPlaying: response.isPlaying,
            progressAtFetch: milliseconds(response.progressMS),
            device: response.device.map {
                PlaybackDevice(name: $0.name, type: $0.type, isActive: $0.isActive ?? false)
            },
            fetchedAt: Date(),
            repeatMode: response.repeatState.flatMap(PlaybackRepeatMode.init(rawValue:))
        )
    }

    private func map(_ item: SpotifyPlayableItem) -> PlaybackItem {
        switch item {
        case .track(let track):
            return PlaybackItem(
                id: track.id, title: track.name, artists: track.artists.map(\.name),
                albumName: track.album?.name, artworkURL: track.album?.images.first?.url,
                duration: milliseconds(track.durationMS) ?? 0, type: .track, uri: track.uri
            )
        case .episode(let episode):
            return PlaybackItem(
                id: episode.id, title: episode.name, artists: episode.show.map { [$0.name] } ?? [],
                albumName: episode.show?.name,
                artworkURL: episode.images?.first?.url ?? episode.show?.images.first?.url,
                duration: milliseconds(episode.durationMS) ?? 0, type: .episode
            )
        case .unknown(let unknown):
            return PlaybackItem(
                id: unknown.id, title: unknown.name ?? "Spotify item", artists: [],
                albumName: nil, artworkURL: nil, duration: 0, type: .unknown
            )
        }
    }

    private func milliseconds(_ value: Int?) -> TimeInterval? {
        value.map { TimeInterval($0) / 1000 }
    }
}
