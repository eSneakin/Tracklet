import AppKit
import SwiftUI

struct WidgetArtwork: View {
    let data: Data?
    let style: ArtworkStyle

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let data, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFill()
                        .saturation(style == .monochrome ? 0 : 1)
                        .blur(radius: style == .blurred ? 6 : 0, opaque: true)
                } else {
                    ZStack {
                        TrackletTheme.subsurface
                        Image(systemName: "music.note").font(.system(size: 30, weight: .light))
                            .foregroundStyle(TrackletTheme.accent)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityHidden(true)
    }
}

struct WidgetPlaybackProgress: View {
    let playback: PlaybackState
    let referenceDate: Date
    let isStale: Bool

    var body: some View {
        if let progress = playback.progress(at: isStale ? playback.fetchedAt : referenceDate), playback.duration > 0 {
            VStack(spacing: 4) {
                if let interval = timerInterval {
                    ProgressView(timerInterval: interval, countsDown: false).labelsHidden()
                        .frame(height: 4)
                } else {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(TrackletTheme.secondaryText.opacity(0.25))
                            Capsule().fill(TrackletTheme.accent)
                                .frame(width: geometry.size.width * min(1, max(0, progress / playback.duration)))
                        }
                    }
                    .frame(height: 4)
                }
                HStack {
                    if let interval = timerInterval {
                        Text(timerInterval: interval, countsDown: false, showsHours: false)
                    } else {
                        Text(Self.time(progress))
                    }
                    Spacer()
                    Text(Self.time(playback.duration))
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(TrackletTheme.secondaryText)
            }
            .tint(TrackletTheme.accent)
        }
    }

    private var timerInterval: ClosedRange<Date>? {
        guard playback.isPlaying, !isStale, let progress = playback.progressAtFetch,
              playback.duration.isFinite, playback.duration > 0, progress.isFinite else { return nil }
        let start = playback.fetchedAt.addingTimeInterval(-min(max(0, progress), playback.duration))
        return start...start.addingTimeInterval(playback.duration)
    }

    private static func time(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let seconds = Int(min(seconds, 86_400 * 365))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}
