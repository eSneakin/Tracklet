import Foundation

enum TrackletWidgetIdentity {
    static let kind = "TrackletNowPlaying"
    static let appGroupInfoKey = "TrackletAppGroup"
    static let appURL = URL(string: "tracklet://widget")!
}

struct WidgetSnapshot: Codable, Equatable {
    enum Interaction: Codable, Equatable {
        case performing(until: Date)
        case failed(String)
    }

    enum Status: String, Codable {
        case disconnected, loading, playing, paused, nothingPlaying, unavailable
    }

    var status: Status = .disconnected
    var playback: PlaybackState?
    var preferences = WidgetPreferences()
    var artworkFileName: String?
    var updatedAt = Date()
    var interaction: Interaction?
    var accountID: String?

    func rememberedPlayback(for accountID: String?) -> PlaybackState? {
        guard let accountID, self.accountID == accountID, status != .disconnected else { return nil }
        return playback?.remembered()
    }

    func isPerformingAction(at date: Date) -> Bool {
        if case .performing(let until) = interaction { return date < until }
        return false
    }

    // A cached playing state is not proof that Spotify is still playing this item.
    var freshnessDeadline: Date? {
        guard let playback, !playback.isLastKnown else { return nil }
        let maximumAge = playback.fetchedAt.addingTimeInterval(180)
        guard playback.isPlaying, playback.duration > 0,
              let progress = playback.progressAtFetch else { return maximumAge }
        return min(maximumAge, playback.fetchedAt.addingTimeInterval(max(0, playback.duration - progress)))
    }

    func isStale(at date: Date) -> Bool {
        freshnessDeadline.map { date >= $0 } ?? false
    }

    func needsReload(comparedTo previous: Self, at date: Date, lastReload: Date) -> Bool {
        if status != previous.status || preferences != previous.preferences ||
            artworkFileName != previous.artworkFileName || playback?.item != previous.playback?.item ||
            playback?.device != previous.playback?.device || playback?.repeatMode != previous.playback?.repeatMode ||
            playback?.source != previous.playback?.source || accountID != previous.accountID ||
            interaction != previous.interaction { return true }
        if let old = previous.playback, let new = playback,
           let expected = old.progress(at: new.fetchedAt), let actual = new.progressAtFetch,
           abs(expected - actual) > 3 { return true }
        return date.timeIntervalSince(lastReload) >= 60
    }
}
