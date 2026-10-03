import SwiftUI

struct ArtworkView: View {
    let url: URL?
    let size: CGFloat
    var cachedFileURL: URL? = nil
    var style: ArtworkStyle = .fullColor

    var body: some View {
        Group {
            if let cachedFileURL, let image = NSImage(contentsOf: cachedFileURL) {
                Image(nsImage: image).resizable().scaledToFill()
            } else if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { placeholder }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .background(TrackletTheme.subsurface)
        .trackletArtworkStyle(style)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.38), radius: 18, y: 10)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [TrackletTheme.accent, TrackletTheme.subsurface, TrackletTheme.background], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "music.note")
                .font(.system(size: size * 0.20, weight: .light))
                .foregroundStyle(TrackletTheme.primaryText.opacity(0.82))
        }
    }
}
