import Foundation
import WidgetKit

struct TrackletWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    var artworkData: Data?

    static var preview: Self {
        let now = Date()
        let item = PlaybackItem(id: "preview", title: "Midnight Drive", artists: ["Tracklet Preview"],
                                albumName: "After Hours", artworkURL: nil, duration: 227, type: .track)
        let playback = PlaybackState(item: item, isPlaying: true, progressAtFetch: 74,
                                     device: PlaybackDevice(name: "Mac", type: "Computer", isActive: true), fetchedAt: now)
        return Self(date: now, snapshot: WidgetSnapshot(status: .playing, playback: playback))
    }
}

struct TrackletTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TrackletWidgetEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (TrackletWidgetEntry) -> Void) {
        completion(context.isPreview ? .preview : readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrackletWidgetEntry>) -> Void) {
        let current = readEntry()
        var entries = [current]
        if let deadline = current.snapshot.freshnessDeadline, deadline > current.date {
            entries.append(TrackletWidgetEntry(date: deadline, snapshot: current.snapshot, artworkData: current.artworkData))
        }
        if case .performing(let until) = current.snapshot.interaction, until > current.date {
            entries.append(TrackletWidgetEntry(date: until, snapshot: current.snapshot, artworkData: current.artworkData))
        }
        entries.sort { $0.date < $1.date }
        // ponytail: the provider reads local snapshots; the host app performs Spotify requests.
        completion(Timeline(entries: entries, policy: .after(current.date.addingTimeInterval(15 * 60))))
    }

    private func readEntry() -> TrackletWidgetEntry {
        let now = Date()
        guard let store = WidgetSharedStore.configured() else {
            return TrackletWidgetEntry(date: now, snapshot: WidgetSnapshot(status: .unavailable))
        }
        do {
            let snapshot = try store.read() ?? WidgetSnapshot()
            let artwork = store.artworkURL(fileName: snapshot.artworkFileName).flatMap { try? Data(contentsOf: $0) }
            return TrackletWidgetEntry(date: now, snapshot: snapshot, artworkData: artwork)
        } catch {
            return TrackletWidgetEntry(date: now, snapshot: WidgetSnapshot(status: .unavailable))
        }
    }
}
