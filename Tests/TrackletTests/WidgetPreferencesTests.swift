import XCTest
@testable import Tracklet

final class WidgetPreferencesTests: XCTestCase {
    func testPreferencesRoundTrip() throws {
        let original = WidgetPreferences(
            appearance: .album,
            artworkStyle: .monochrome,
            showsPrevious: false,
            showsPlayPause: true,
            showsNext: false
        )
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(WidgetPreferences.self, from: data), original)
    }

    func testSpotifyProfileWithoutImagesDecodes() throws {
        let data = Data(#"{"display_name":"Spotify user"}"#.utf8)
        let profile = try JSONDecoder().decode(SpotifyUser.self, from: data)
        XCTAssertEqual(profile.displayName, "Spotify user")
        XCTAssertTrue(profile.images.isEmpty)
    }
}
