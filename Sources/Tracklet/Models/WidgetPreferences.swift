import Foundation

enum WidgetAppearance: String, CaseIterable, Codable, Hashable, Identifiable {
    case compact, player, album, minimal

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum ArtworkStyle: String, CaseIterable, Codable, Hashable, Identifiable {
    case fullColor, blurred, monochrome

    var id: String { rawValue }
    var title: String {
        switch self {
        case .fullColor: "Full Color"
        case .blurred: "Blurred"
        case .monochrome: "Monochrome"
        }
    }
}

struct WidgetPreferences: Codable, Equatable {
    var appearance: WidgetAppearance = .compact
    var artworkStyle: ArtworkStyle = .fullColor
    var showsPrevious = true
    var showsPlayPause = true
    var showsNext = true
}
