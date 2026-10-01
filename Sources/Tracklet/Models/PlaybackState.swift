import Foundation

enum PlaybackItemType: String, Codable { case track, episode, unknown }

enum PlaybackRepeatMode: String, Codable { case off, track, context }

enum PlaybackAction: String, Codable, CaseIterable, Sendable {
    case previous, play, pause, next, repeatTrack, repeatOff
}

struct PlaybackItem: Codable, Equatable {
    let id: String?
    let title: String
    let artists: [String]
    let albumName: String?
    let artworkURL: URL?
    let duration: TimeInterval
    let type: PlaybackItemType
    var uri: String? = nil
}

struct PlaybackDevice: Codable, Equatable {
    let name: String
    let type: String?
    let isActive: Bool
}

struct PlaybackState: Codable, Equatable {
    enum Source: String, Codable { case lastKnown }
    let item: PlaybackItem?
    let isPlaying: Bool
    let progressAtFetch: TimeInterval?
    let device: PlaybackDevice?
    let fetchedAt: Date
    var repeatMode: PlaybackRepeatMode? = nil
    var source: Source? = nil

    var isLastKnown: Bool { source == .lastKnown }

    /// Retain only confirmed progress, never extrapolate through an unknown/offline interval.
    func remembered() -> Self {
        Self(item: item, isPlaying: false, progressAtFetch: progress(at: fetchedAt),
             device: nil, fetchedAt: fetchedAt, repeatMode: repeatMode, source: .lastKnown)
    }

    var duration: TimeInterval { item?.duration ?? 0 }

    func progress(at date: Date = Date()) -> TimeInterval? {
        guard let progressAtFetch else { return nil }
        let elapsed = isPlaying ? max(0, date.timeIntervalSince(fetchedAt)) : 0
        return min(max(0, progressAtFetch + elapsed), duration)
    }
}
