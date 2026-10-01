import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel
    @ObservedObject var playbackModel: PlaybackViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                AccountConnectionView(account: model.account, isConnecting: model.isConnecting, errorMessage: model.errorMessage, onConnect: model.connectSpotify, onDisconnect: model.disconnectSpotify)
                PlaybackView(model: playbackModel)
                SettingsSection(title: "Widget") {
                    SelectionRow(selection: $model.preferences.artworkStyle, options: ArtworkStyle.allCases)
                }
                SettingsSection(title: "Appearance") {
                    SelectionRow(selection: $model.preferences.appearance, options: WidgetAppearance.allCases)
                }
            }
            .padding(34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(TrackletTheme.background)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Tracklet")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(TrackletTheme.primaryText)
                if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                    Text("v\(version)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(TrackletTheme.secondaryText)
                        .accessibilityLabel("Version \(version)")
                }
            }
            Text("A focused Spotify companion for macOS")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(TrackletTheme.secondaryText)
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .bold))
                .tracking(1.7)
                .foregroundStyle(TrackletTheme.secondaryText)
            VStack(spacing: 0) { content }
                .background(TrackletTheme.card, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct SelectionRow<Option: CaseIterable & Hashable & Identifiable & RawRepresentable>: View where Option.RawValue == String {
    @Binding var selection: Option
    let options: [Option]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(options) { option in
                Button { withAnimation(.easeOut(duration: 0.16)) { selection = option } } label: {
                    HStack {
                        Text(optionTitle(option))
                            .font(.system(size: 15, weight: selection == option ? .semibold : .regular))
                            .foregroundStyle(TrackletTheme.primaryText)
                        Spacer()
                        Image(systemName: selection == option ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(selection == option ? TrackletTheme.accent : TrackletTheme.secondaryText)
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .trackletClickableCursor()
            }
        }
    }

    private func optionTitle(_ option: Option) -> String {
        option.rawValue == "fullColor" ? "Full Color" : option.rawValue.capitalized
    }
}
