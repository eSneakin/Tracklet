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

    func testTrackAndEpisodePlaybackItemsDecode() throws {
        let track = Data(#"{"type":"track","id":"track-1","name":"Song","duration_ms":180000,"artists":[{"name":"Artist"}],"album":{"name":"Album","images":[]}}"#.utf8)
        let episode = Data(#"{"type":"episode","id":"episode-1","name":"Episode","duration_ms":60000,"show":{"name":"Show","images":[]}}"#.utf8)
        let decodedTrack = try JSONDecoder().decode(SpotifyPlayableItem.self, from: track)
        let decodedEpisode = try JSONDecoder().decode(SpotifyPlayableItem.self, from: episode)
        if case .track = decodedTrack {} else { XCTFail("Expected track") }
        if case .episode = decodedEpisode {} else { XCTFail("Expected episode") }
    }

    func testPlayingProgressIsClampedAndAdvances() {
        let fetchedAt = Date(timeIntervalSince1970: 100)
        let item = PlaybackItem(id: nil, title: "Song", artists: [], albumName: nil, artworkURL: nil, duration: 10, type: .track)
        let state = PlaybackState(item: item, isPlaying: true, progressAtFetch: 8, device: nil, fetchedAt: fetchedAt)
        XCTAssertEqual(state.progress(at: Date(timeIntervalSince1970: 101)), 9)
        XCTAssertEqual(state.progress(at: Date(timeIntervalSince1970: 105)), 10)
    }

    func testTrackAndEpisodeCollectionsShareOptionalArtworkDecoding() throws {
        for images in ["", #", "images": null"#, #", "images": []"#] {
            let track = Data("""
                {"type":"track","name":"Song","duration_ms":1000,"artists":[],
                 "album":{"name":"Album"\(images)}}
                """.utf8)
            let episode = Data("""
                {"type":"episode","name":"Episode","duration_ms":1000,
                 "show":{"name":"Show"\(images)}}
                """.utf8)
            guard case .track(let decodedTrack) = try JSONDecoder().decode(SpotifyPlayableItem.self, from: track),
                  case .episode(let decodedEpisode) = try JSONDecoder().decode(SpotifyPlayableItem.self, from: episode)
            else { return XCTFail("Unexpected item type") }
            XCTAssertEqual(decodedTrack.album?.name, "Album")
            XCTAssertEqual(decodedTrack.album?.images.count, 0)
            XCTAssertEqual(decodedEpisode.show?.name, "Show")
            XCTAssertEqual(decodedEpisode.show?.images.count, 0)
        }
        let valid = Data(#"{"name":"Collection","images":[{"url":"https://example.com/art.jpg"}]}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(SpotifyCollectionDTO.self, from: valid).images.first?.url,
                       URL(string: "https://example.com/art.jpg"))
        let malformed = Data(#"{"name":"Collection","images":"invalid"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(SpotifyCollectionDTO.self, from: malformed))
    }
}
