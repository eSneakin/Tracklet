import SwiftUI

struct PlaybackControls: View {
    let isPlaying: Bool
    let isEnabled: Bool
    let isBusy: Bool
    let onPrevious: () -> Void
    let onTogglePlayPause: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            controlButton(icon: "backward.fill", label: "Previous", action: onPrevious)
            controlButton(icon: isPlaying ? "pause.fill" : "play.fill", label: isPlaying ? "Pause" : "Play", prominent: true, action: onTogglePlayPause)
            controlButton(icon: "forward.fill", label: "Next", action: onNext)
        }
        .disabled(!isEnabled || isBusy)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private func controlButton(icon: String, label: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: prominent ? 17 : 13, weight: .semibold))
        }
        .buttonStyle(PlaybackControlButtonStyle(prominent: prominent, isBusy: isBusy))
        .trackletClickableCursor()
        .accessibilityLabel(label)
    }
}

private struct PlaybackControlButtonStyle: ButtonStyle {
    let prominent: Bool
    let isBusy: Bool

    func makeBody(configuration: Configuration) -> some View {
        PlaybackControlButtonLabel(
            configuration: configuration,
            prominent: prominent,
            isBusy: isBusy
        )
    }
}

private struct PlaybackControlButtonLabel: View {
    let configuration: ButtonStyle.Configuration
    let prominent: Bool
    let isBusy: Bool
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .foregroundStyle(prominent ? TrackletTheme.background : TrackletTheme.primaryText)
            .frame(width: prominent ? 48 : 36, height: prominent ? 48 : 36)
            .background(background, in: Circle())
            .overlay(Circle().stroke(TrackletTheme.border.opacity(prominent ? 0 : 0.45), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.95 : (isHovered ? 1.03 : 1))
            .opacity(configuration.isPressed ? 0.78 : (isBusy ? 0.62 : 1))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .onHover { isHovered = $0 && isEnabled }
            .onChange(of: isEnabled) { if !$0 { isHovered = false } }
    }

    private var background: Color {
        if prominent { return isHovered ? TrackletTheme.accent.opacity(0.88) : TrackletTheme.accent }
        return isHovered ? TrackletTheme.border.opacity(0.72) : TrackletTheme.subsurface
    }
}
