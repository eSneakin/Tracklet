import SwiftUI
import WidgetKit

struct WidgetPlaybackView: View {
    let entry: TrackletWidgetEntry
    let family: WidgetFamily
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var item: PlaybackItem? { snapshot.playback?.item }
    private var isStale: Bool { snapshot.isStale(at: entry.date) }
    private var primary: Color { renderingMode == .fullColor ? TrackletTheme.primaryText : .primary }
    private var secondary: Color { renderingMode == .fullColor ? TrackletTheme.secondaryText : .secondary }
    private var minimal: Bool { snapshot.preferences.appearance == .minimal }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let item {
                    switch family {
                    case .systemSmall: small(item, size: geometry.size)
                    case .systemLarge: large(item, size: geometry.size)
                    default: medium(item, size: geometry.size)
                    }
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(primary)
        .accessibilityElement(children: .contain)
    }

    private func small(_ item: PlaybackItem, size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if minimal {
                brand
                Spacer(minLength: 0)
            } else {
                artwork.frame(height: max(34, size.height - 68))
                    .frame(maxWidth: .infinity)
            }
            metadata(item, titleSize: 13, includeAlbum: false)
            status
        }
    }

    private func medium(_ item: PlaybackItem, size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                if !minimal {
                    artwork.frame(width: min(76, max(44, size.height - 64)), height: min(76, max(44, size.height - 64)))
                }
                VStack(alignment: .leading, spacing: 6) {
                    brand
                    metadata(item, titleSize: 15, includeAlbum: snapshot.preferences.appearance != .compact)
                    status
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            if let playback = snapshot.playback {
                WidgetPlaybackProgress(playback: playback, referenceDate: entry.date, isStale: isStale)
                device(playback.device)
            }
        }
    }

    private func large(_ item: PlaybackItem, size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { brand; Spacer(); status }.fixedSize(horizontal: false, vertical: true)
            if !minimal {
                // Artwork takes remaining height; metadata, device and controls never overflow.
                GeometryReader { available in
                    let side = min(available.size.width, available.size.height)
                    artwork.frame(width: side, height: side)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(minHeight: 32)
            } else {
                Spacer(minLength: 0)
            }
            metadata(item, titleSize: 17, includeAlbum: true)
                .fixedSize(horizontal: false, vertical: true)
            if let playback = snapshot.playback {
                WidgetPlaybackProgress(playback: playback, referenceDate: entry.date, isStale: isStale)
                    .fixedSize(horizontal: false, vertical: true)
                WidgetPlaybackControls(playback: isStale ? playback.remembered() : playback, preferences: snapshot.preferences,
                                       isBusy: snapshot.isPerformingAction(at: entry.date))
                    .fixedSize(horizontal: false, vertical: true)
                device(playback.device).fixedSize(horizontal: false, vertical: true)
                if case .failed(let message) = snapshot.interaction {
                    Text(message).font(.system(size: 10)).foregroundStyle(TrackletTheme.destructive)
                        .lineLimit(1).help(message).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func device(_ device: PlaybackDevice?) -> some View {
        if let device {
            Label(device.name, systemImage: device.type?.lowercased() == "computer" ? "laptopcomputer" : "hifispeaker.fill")
                .font(.system(size: 10)).foregroundStyle(secondary).lineLimit(1)
                .accessibilityLabel("Playback device: \(device.name)")
        }
    }

    private var artwork: some View {
        WidgetArtwork(data: entry.artworkData, style: snapshot.preferences.artworkStyle)
    }

    private var brand: some View {
        Label("Tracklet", systemImage: "waveform")
            .font(.system(size: 10, weight: .semibold)).foregroundStyle(TrackletTheme.accent)
            .widgetAccentable()
    }

    private func metadata(_ item: PlaybackItem, titleSize: CGFloat, includeAlbum: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title).font(.system(size: titleSize, weight: .semibold))
                .lineLimit(1).truncationMode(.tail)
            if !item.artists.isEmpty {
                Text(item.artists.joined(separator: ", "))
                    .font(.system(size: family == .systemSmall ? 11 : 12))
                    .foregroundStyle(secondary).lineLimit(1)
            }
            if includeAlbum, let album = item.albumName {
                Text(album).font(.system(size: 11)).foregroundStyle(secondary.opacity(0.8)).lineLimit(1)
            }
        }
    }

    private var status: some View {
        let busy = snapshot.isPerformingAction(at: entry.date)
        let remembered = snapshot.playback?.isLastKnown == true
        return Label(busy ? "Updating" : (remembered ? "Last played" : (isStale ? "Last synced" : (snapshot.status == .playing ? "Playing" : "Paused"))),
              systemImage: busy ? "arrow.triangle.2.circlepath" : (remembered || isStale ? "clock" : (snapshot.status == .playing ? "waveform" : "pause.fill")))
            .font(.system(size: 10, weight: .medium)).foregroundStyle(secondary)
            .lineLimit(1)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            brand
            Spacer(minLength: 0)
            Image(systemName: emptyIcon).font(.system(size: family == .systemSmall ? 24 : 32))
                .foregroundStyle(TrackletTheme.accent)
            Text(emptyTitle).font(.system(size: family == .systemSmall ? 14 : 18, weight: .semibold))
            Text(emptyMessage).font(.system(size: 12)).foregroundStyle(secondary)
                .lineLimit(family == .systemSmall ? 2 : 3)
            Spacer(minLength: 0)
        }
    }

    private var emptyIcon: String {
        switch snapshot.status {
        case .disconnected: "person.crop.circle"
        case .loading: "arrow.triangle.2.circlepath"
        case .unavailable: "exclamationmark.circle"
        default: "music.note"
        }
    }

    private var emptyTitle: String {
        switch snapshot.status {
        case .disconnected: "Connect Spotify"
        case .loading: "Syncing playback"
        case .unavailable: "Open Tracklet"
        default: "Nothing playing"
        }
    }

    private var emptyMessage: String {
        switch snapshot.status {
        case .disconnected: "Open Tracklet to connect."
        case .loading: "Waiting for Spotify."
        case .unavailable: "Open the app to sync your music."
        default: "Start playback in Spotify."
        }
    }
}
