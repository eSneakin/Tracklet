import SwiftUI

struct AccountConnectionView: View {
    let account: SpotifyAccount?
    let isConnecting: Bool
    let errorMessage: String?
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        TrackletCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    avatar
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Spotify")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(TrackletTheme.secondaryText)
                        Text(account?.displayName ?? "Not connected")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(TrackletTheme.primaryText)
                        if account != nil {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(TrackletTheme.success)
                        }
                    }
                    Spacer()
                    Button(account == nil ? "Connect" : "Disconnect") {
                        account == nil ? onConnect() : onDisconnect()
                    }
                    .buttonStyle(TrackletButtonStyle(prominent: account == nil, destructive: account != nil))
                    .trackletClickableCursor()
                    .disabled(isConnecting)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarURL = account?.avatarURL {
            AsyncImage(url: avatarURL) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { placeholder }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Image(systemName: "person.crop.circle")
            .font(.system(size: 30))
            .foregroundStyle(TrackletTheme.secondaryText)
            .frame(width: 48, height: 48)
    }
}
