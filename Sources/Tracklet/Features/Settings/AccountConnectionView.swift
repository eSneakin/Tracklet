import SwiftUI

struct AccountConnectionView: View {
    let account: SpotifyAccount?
    let isConnecting: Bool
    let errorMessage: String?
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                avatar
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connected as")
                        .font(.system(size: 16, weight: .bold))
                    Text(account?.displayName ?? "Spotify")
                        .font(.system(size: 17, weight: .bold))
                    if account != nil {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.spotifyGreen)
                    } else {
                        Text("Not connected")
                        .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            HStack {
                Spacer()
                Button(account == nil ? "Connect Spotify" : "Disconnect") {
                    account == nil ? onConnect() : onDisconnect()
                }
                .buttonStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(account == nil ? .black : .white)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(account == nil ? Color.spotifyGreen : Color.trackletButton, in: Capsule())
                .disabled(isConnecting)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(28)
        .background(Color.trackletSurface, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarURL = account?.avatarURL {
            AsyncImage(url: avatarURL) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { placeholder }
            }
            .frame(width: 58, height: 58)
            .clipShape(Circle())
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Image(systemName: account == nil ? "person.crop.circle" : "person.crop.circle.fill")
            .font(.system(size: 30))
            .foregroundStyle(account == nil ? .secondary : Color.spotifyGreen)
            .frame(width: 58, height: 58)
    }
}

private extension Color {
    static let spotifyGreen = Color(red: 0.118, green: 0.843, blue: 0.376)
    static let trackletSurface = Color(red: 0.095, green: 0.095, blue: 0.095)
    static let trackletButton = Color(red: 0.13, green: 0.13, blue: 0.13)
}
