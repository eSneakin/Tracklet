import Foundation

struct SpotifyAccount: Equatable {
    let displayName: String
    let avatarURL: URL?
}

extension SpotifyAccount {
    init(user: SpotifyUser) {
        self.init(displayName: user.displayName ?? "Spotify user", avatarURL: user.images.first?.url)
    }
}
