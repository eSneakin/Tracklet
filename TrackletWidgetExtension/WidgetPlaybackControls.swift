import SwiftUI

struct WidgetPlaybackControls: View {
    let playback: PlaybackState
    let preferences: WidgetPreferences
    let isBusy: Bool

    var body: some View {
        HStack(spacing: 14) {
            if preferences.showsPrevious {
                control(.previous, symbol: "backward.fill", label: "Previous song")
            }
            if preferences.showsPlayPause {
                control(playback.isPlaying ? .pause : .play,
                        symbol: playback.isPlaying ? "pause.fill" : "play.fill",
                        label: playback.isPlaying ? "Pause" : "Play", prominent: true)
            }
            if preferences.showsNext {
                control(.next, symbol: "forward.fill", label: "Next song")
            }
            control(playback.repeatMode == .track ? .repeatOff : .repeatTrack,
                    symbol: playback.repeatMode == .track ? "repeat.1" : "repeat",
                    label: playback.repeatMode == .track ? "Turn repeat off" : "Repeat song",
                    selected: playback.repeatMode == .track)
                .accessibilityValue(playback.repeatMode == .track ? "On" : "Off")
        }
        .frame(maxWidth: .infinity)
        // Cached device activity is not authoritative; the host revalidates every command.
        .disabled(isBusy || playback.item == nil)
        .invalidatableContent()
    }

    private func control(_ action: PlaybackAction, symbol: String, label: String,
                         prominent: Bool = false, selected: Bool = false) -> some View {
        Button(intent: WidgetPlaybackIntent(action: action)) {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 16 : 14, weight: .semibold))
                .frame(width: prominent ? 38 : 32, height: prominent ? 38 : 32)
                .contentShape(Circle())
        }
        .buttonStyle(WidgetPlaybackButtonStyle(prominent: prominent, selected: selected))
        .accessibilityLabel(label)
        .help(label)
    }
}

private struct WidgetPlaybackButtonStyle: ButtonStyle {
    let prominent: Bool
    let selected: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(prominent ? TrackletTheme.background : (selected ? TrackletTheme.accent : TrackletTheme.primaryText))
            .background(prominent ? TrackletTheme.accent : TrackletTheme.subsurface, in: Circle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}
