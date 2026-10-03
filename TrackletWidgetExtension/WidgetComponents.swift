import AppKit
import SwiftUI

struct WidgetArtwork: View {
    let data: Data?
    let style: ArtworkStyle

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let data, let image = WidgetArtworkImage.make(data: data, style: style) {
                    Image(decorative: image, scale: 1).renderingMode(.original).resizable().scaledToFill()
                } else {
                    ZStack {
                        style == .monochrome ? Color(white: 0.2) : TrackletTheme.subsurface
                        Image(systemName: "music.note").font(.system(size: 30, weight: .light))
                            .foregroundStyle(style == .monochrome ? Color(white: 0.8) : TrackletTheme.accent)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .blur(radius: style == .blurred ? 6 : 0, opaque: true)
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
                        Text(PlaybackTime.format(progress))
                    }
                    Spacer()
                    Text(PlaybackTime.format(playback.duration))
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

}
