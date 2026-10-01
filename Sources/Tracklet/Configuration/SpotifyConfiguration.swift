import Foundation

struct SpotifyConfiguration {
    let clientID: String
    let redirectURI: URL

    // Spotify Client ID is public; keep configuration centralized, never in UI/auth flow.
    private static let bundledClientID = "8d034cfb4a6f4fa6b0cfe1525f5e8c3a"

    static let scopes = ["user-read-private", "user-read-email", "user-read-currently-playing", "user-read-playback-state", "user-modify-playback-state"]

    static var current: SpotifyConfiguration {
        let info = Bundle.main
        let clientID = (info.object(forInfoDictionaryKey: "SpotifyClientID") as? String)
            ?? ProcessInfo.processInfo.environment["SPOTIFY_CLIENT_ID"]
            ?? bundledClientID
        let redirectValue = (info.object(forInfoDictionaryKey: "SpotifyRedirectURI") as? String)
            ?? ProcessInfo.processInfo.environment["SPOTIFY_REDIRECT_URI"]
            ?? "tracklet://callback"
        return SpotifyConfiguration(
            clientID: clientID,
            redirectURI: URL(string: redirectValue) ?? URL(string: "tracklet://callback")!
        )
    }
}
