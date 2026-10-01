// Compile with the widget views/shared sources and -D WIDGET_EXTENSION; renders without Spotify.
import AppKit
import SwiftUI
import WidgetKit

@main
struct RenderWidgetPreviews {
    @MainActor
    static func main() throws {
        let directory = URL(fileURLWithPath: ".build/widget-previews", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date()
        let item = PlaybackItem(id: "preview", title: "Punto Medio — Unplugged", artists: ["Omy de Oro, Omega"],
                                albumName: "Punto Medio (Unplugged)", artworkURL: nil, duration: 253, type: .track)
        let state = PlaybackState(item: item, isPlaying: false, progressAtFetch: 3,
                                  device: PlaybackDevice(name: "Emmanuel’s MacBook Air", type: "Computer", isActive: true),
                                  fetchedAt: now, repeatMode: .track)
        let sizes: [(String, WidgetFamily, CGFloat, CGFloat)] = [
            ("small", .systemSmall, 164, 164), ("medium", .systemMedium, 344, 164),
            ("large", .systemLarge, 344, 344), ("large-error", .systemLarge, 344, 344),
            ("large-last-played", .systemLarge, 344, 344)
        ]
        for (name, family, width, height) in sizes {
            var snapshot = WidgetSnapshot(status: .paused, playback: state)
            if name == "large-error" { snapshot.interaction = .failed("No active Spotify playback device found.") }
            if name == "large-last-played" {
                snapshot.playback = state.remembered()
                snapshot.interaction = .failed("Open Spotify to continue. No active playback device found.")
            }
            let view = WidgetPlaybackView(entry: TrackletWidgetEntry(date: now, snapshot: snapshot), family: family)
                .padding(16).frame(width: width, height: height)
                .background(TrackletTheme.background).preferredColorScheme(.dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try png.write(to: directory.appendingPathComponent("\(name).png"))
            print("Rendered \(name): \(Int(width)) × \(Int(height)) pt")
        }
    }
}
