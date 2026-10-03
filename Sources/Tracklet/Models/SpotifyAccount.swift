import Foundation

struct SpotifyAccount: Equatable {
    let displayName: String
    let avatarURL: URL?
    // Keep Spotify's stable identity separate from the display name used by the UI.
    var id: String? = nil
}

extension SpotifyAccount {
    init(user: SpotifyUser) {
        self.init(displayName: user.displayName ?? "Spotify user", avatarURL: user.images.first?.url, id: user.id)
    }
}
