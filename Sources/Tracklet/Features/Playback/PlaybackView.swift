import SwiftUI

struct PlaybackView: View {
    @ObservedObject var model: PlaybackViewModel

    var body: some View {
        TrackletCard {
            Group {
                switch model.state {
                case .idle, .loading:
                    loadingView
                case .playing(let playback), .paused(let playback), .lastPlayed(let playback):
                    playbackView(playback)
                case .nothingPlaying:
                    emptyView
                case .error(let message):
                    errorView(message)
                }
            }
            .padding(18)
        }
    }

    private var loadingView: some View {
        HStack(spacing: 14) {
            ProgressView().controlSize(.small).tint(TrackletTheme.accent)
            Text("Loading playback")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TrackletTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
    }

    private var emptyView: some View {
        HStack(spacing: 14) {
            ArtworkView(url: nil, size: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing playing")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(TrackletTheme.primaryText)
                Text("Start playback in Spotify")
                    .font(.system(size: 12))
                    .foregroundStyle(TrackletTheme.secondaryText)
            }
            Spacer()
        }
        .frame(minHeight: 96)
    }

    private func playbackView(_ playback: PlaybackState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ArtworkView(url: playback.item?.artworkURL, size: 88, cachedFileURL: model.cachedArtworkURL)
                VStack(alignment: .leading, spacing: 4) {
                    Text(playback.item?.title ?? "Unknown title")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(TrackletTheme.primaryText)
                        .lineLimit(1)
                    Text(playback.item?.artists.joined(separator: ", ") ?? "Unknown artist")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(TrackletTheme.secondaryText)
                        .lineLimit(1)
                    if let album = playback.item?.albumName {
                        Text(album)
                            .font(.system(size: 12))
                            .foregroundStyle(TrackletTheme.secondaryText.opacity(0.76))
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let progress = playback.progress(at: context.date) ?? 0
                VStack(spacing: 5) {
                    if playback.duration > 0 {
                        ProgressView(value: progress, total: playback.duration)
                            .tint(TrackletTheme.accent)
                    } else {
                        ProgressView(value: 0).tint(TrackletTheme.accent)
                    }
                    HStack {
                        Text(formatTime(progress))
                        Spacer()
                        Text(formatTime(playback.duration))
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(TrackletTheme.secondaryText)
                }
            }
            if playback.isLastKnown {
                Label("Last played", systemImage: "clock")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TrackletTheme.secondaryText)
            } else if let device = playback.device {
                HStack(spacing: 8) {
                    Label("\(playback.isPlaying ? "Playing" : "Paused") on \(device.name)", systemImage: "speaker.wave.2.fill")
                    if model.isRefreshing {
                        ProgressView().controlSize(.mini).tint(TrackletTheme.accent)
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TrackletTheme.secondaryText)
            }
            PlaybackControls(
                isPlaying: playback.isPlaying,
                isEnabled: model.canControlPlayback,
                isBusy: model.isPerformingPlaybackAction,
                onPrevious: model.previous,
                onTogglePlayPause: model.togglePlayPause,
                onNext: model.next
            )
            .frame(maxWidth: .infinity)
            if let message = model.actionError ?? model.refreshError {
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TrackletTheme.secondaryText)
                .lineLimit(3)
            Spacer()
            Button { Task { await model.refresh() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .trackletClickableCursor()
        }
        .frame(minHeight: 96)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        return "\(Int(seconds) / 60):\(String(format: "%02d", Int(seconds) % 60))"
    }
}
