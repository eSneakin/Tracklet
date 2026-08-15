import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                AccountConnectionView(account: model.account, isConnecting: model.isConnecting, errorMessage: model.errorMessage, onConnect: model.connectSpotify, onDisconnect: model.disconnectSpotify)
                SettingsSection(title: "Appearance") {
                    SelectionRow(selection: $model.preferences.appearance, options: WidgetAppearance.allCases)
                }
                SettingsSection(title: "Artwork") {
                    SelectionRow(selection: $model.preferences.artworkStyle, options: ArtworkStyle.allCases)
                }
                SettingsSection(title: "Controls") {
                    ToggleSettingRow(title: "Previous", icon: "backward.fill", isOn: $model.preferences.showsPrevious)
                    ToggleSettingRow(title: "Play / Pause", icon: "playpause.fill", isOn: $model.preferences.showsPlayPause)
                    ToggleSettingRow(title: "Next", icon: "forward.fill", isOn: $model.preferences.showsNext)
                }
            }
            .padding(34)
        }
        .background(Color.trackletBackground)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Tracklet").font(.system(size: 34, weight: .bold, design: .rounded))
            Text("Widget preferences").font(.system(size: 18, weight: .medium)).foregroundStyle(.secondary)
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.system(size: 13, weight: .bold)).tracking(1.9).foregroundStyle(.secondary)
            VStack(spacing: 0) { content }
                .background(Color.trackletSurface, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct SelectionRow<Option: CaseIterable & Hashable & Identifiable & RawRepresentable>: View where Option.RawValue == String {
    @Binding var selection: Option
    let options: [Option]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(options) { option in
                Button { selection = option } label: {
                    HStack {
                        Text(optionTitle(option)).font(.system(size: 17, weight: selection == option ? .bold : .medium))
                        Spacer()
                        Image(systemName: selection == option ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 23))
                            .foregroundStyle(selection == option ? Color.spotifyGreen : .secondary)
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func optionTitle(_ option: Option) -> String {
        option.rawValue == "fullColor" ? "Full Color" : option.rawValue.capitalized
    }
}

struct ToggleSettingRow: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) { Label(title, systemImage: icon) }
            .toggleStyle(.switch)
            .tint(Color.spotifyGreen)
            .font(.system(size: 16, weight: .medium))
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
    }
}

private extension Color {
    static let trackletBackground = Color(red: 0.055, green: 0.055, blue: 0.055)
    static let trackletSurface = Color(red: 0.095, green: 0.095, blue: 0.095)
    static let spotifyGreen = Color(red: 0.118, green: 0.843, blue: 0.376)
}
