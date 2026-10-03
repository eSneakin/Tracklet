import SwiftUI

enum TrackletTheme {
    static let accent = Color(red: 0.055, green: 0.647, blue: 0.914) // #0EA5E9
    static let background = Color(red: 0.008, green: 0.024, blue: 0.090) // #020617
    static let card = Color(red: 0.078, green: 0.145, blue: 0.227) // #14253A
    static let subsurface = Color(red: 0.110, green: 0.192, blue: 0.290) // #1C314A
    static let input = Color(red: 0.094, green: 0.165, blue: 0.251) // #182A40
    static let border = Color(red: 0.220, green: 0.318, blue: 0.427) // #38516D
    static let primaryText = Color(red: 0.910, green: 0.949, blue: 1.000) // #E8F2FF
    static let secondaryText = Color(red: 0.718, green: 0.780, blue: 0.851) // #B7C7D9
    static let success = Color(red: 0.376, green: 0.647, blue: 0.984) // #60A5FA
    static let destructive = Color(red: 0.973, green: 0.443, blue: 0.443) // #F87171
}

extension View {
    /// App treatment for cached, remote and placeholder artwork. Widgets bake grayscale
    /// into their image pixels instead, to survive WidgetKit's remote rendering.
    func trackletArtworkStyle(_ style: ArtworkStyle) -> some View {
        saturation(style == .monochrome ? 0 : 1)
            .blur(radius: style == .blurred ? 6 : 0, opaque: true)
    }
}
