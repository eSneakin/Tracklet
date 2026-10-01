import SwiftUI

struct TrackletCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .background(TrackletTheme.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(TrackletTheme.border.opacity(0.30), lineWidth: 1)
            }
    }
}

struct TrackletButtonStyle: ButtonStyle {
    let prominent: Bool
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(prominent && !destructive ? TrackletTheme.background : TrackletTheme.primaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(destructive ? TrackletTheme.destructive : (prominent ? TrackletTheme.accent : TrackletTheme.subsurface), in: Capsule())
            .overlay(Capsule().stroke(TrackletTheme.border.opacity(prominent ? 0 : 0.55), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
