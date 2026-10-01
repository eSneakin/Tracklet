import SwiftUI
import WidgetKit

@main
struct TrackletWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TrackletWidgetIdentity.kind, provider: TrackletTimelineProvider()) { entry in
            TrackletWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Tracklet")
        .description("Your latest Spotify playback, in a size that fits your desktop.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct TrackletWidgetEntryView: View {
    let entry: TrackletWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        WidgetPlaybackView(entry: entry, family: family)
            .containerBackground(for: .widget) { TrackletTheme.background }
            .widgetURL(TrackletWidgetIdentity.appURL)
    }
}

#Preview(as: .systemSmall) { TrackletWidget() } timeline: { TrackletWidgetEntry.preview }
#Preview(as: .systemMedium) { TrackletWidget() } timeline: { TrackletWidgetEntry.preview }
#Preview(as: .systemLarge) { TrackletWidget() } timeline: { TrackletWidgetEntry.preview }
