import Combine
import XCTest
@testable import Tracklet

final class WidgetPlaybackTests: XCTestCase {
    @MainActor
    func testVisiblePlaybackPayloadIsSharedByLiveAndRememberedStates() {
        let live = PlaybackState(item: nil, isPlaying: true, progressAtFetch: 0,
                                 device: nil, fetchedAt: Date(timeIntervalSince1970: 100))
        let saved = live.remembered()
        XCTAssertEqual(PlaybackViewModel.State.playing(live).playback, live)
        XCTAssertEqual(PlaybackViewModel.State.paused(live).playback, live)
        XCTAssertEqual(PlaybackViewModel.State.lastPlayed(saved).playback, saved)
        let emptyStates: [PlaybackViewModel.State] = [.idle, .loading, .nothingPlaying, .error("Offline")]
        for state in emptyStates { XCTAssertNil(state.playback) }
    }

    @MainActor
    func testAllCommandsUseExistingClientAndRefreshConfirmedState() async throws {
        let (model, fixture) = makeModel()
        let checks: [(PlaybackAction, String, String, String?)] = [
            (.previous, "POST", "/v1/me/player/previous", nil),
            (.play, "PUT", "/v1/me/player/play", nil),
            (.pause, "PUT", "/v1/me/player/pause", nil),
            (.next, "POST", "/v1/me/player/next", nil),
            (.repeatTrack, "PUT", "/v1/me/player/repeat", "state=track"),
            (.repeatOff, "PUT", "/v1/me/player/repeat", "state=off")
        ]
        for (action, method, path, query) in checks {
            await model.performWidgetAction(action)
            let command = try XCTUnwrap(fixture.commands.last)
            XCTAssertEqual(command.httpMethod, method)
            XCTAssertEqual(command.url?.path, path)
            XCTAssertEqual(command.url?.query, query)
            let state = try playback(model)
            XCTAssertEqual(state.isPlaying, fixture.isPlaying)
            XCTAssertEqual(state.item?.title, fixture.title)
            XCTAssertEqual(state.repeatMode?.rawValue, fixture.repeatMode)
            XCTAssertNil(model.actionError)
            try await Task.sleep(for: .milliseconds(750)) // Intentional tap cooldown.
        }
        XCTAssertEqual(fixture.commands.count, 6)
        XCTAssertEqual(fixture.reads, 12) // Preflight + one confirmation; no retry loop.
    }

    @MainActor
    func testConcurrentTapsAndImmediateRepeatSendOneCommand() async {
        let (model, fixture) = makeModel()
        let first = Task { await model.performWidgetAction(.next) }
        await Task.yield()
        await model.performWidgetAction(.next)
        await first.value
        await model.performWidgetAction(.next)
        XCTAssertEqual(fixture.commands.count, 1)
        XCTAssertFalse(model.isPerformingPlaybackAction)
    }

    @MainActor
    func testPreviousRestartsAtThreeSecondsOtherwiseSkipsForPlayingAndPaused() async throws {
        for playing in [false, true] {
            for milliseconds in [0, 2_999, 3_000, 3_001, 120_000] {
                let (model, fixture) = makeModel(progressMS: milliseconds, isPlaying: playing)
                await model.performWidgetAction(.previous)
                let command = try XCTUnwrap(fixture.commands.first)
                let restart = milliseconds >= 3_000
                XCTAssertEqual(command.httpMethod, restart ? "PUT" : "POST")
                XCTAssertEqual(command.url?.path, restart ? "/v1/me/player/seek" : "/v1/me/player/previous")
                XCTAssertEqual(command.url?.query, restart ? "position_ms=0" : nil)
                XCTAssertEqual(fixture.commands.count, 1)
                XCTAssertEqual(fixture.reads, 2)
                let state = try playback(model)
                XCTAssertEqual(state.item?.title, restart ? "Song" : "Previous song")
                XCTAssertEqual(state.progressAtFetch, 0)
                XCTAssertEqual(state.isPlaying, playing) // Seeking must not resume a paused song.
                XCTAssertEqual(state.repeatMode, .off)
                XCTAssertNil(model.actionError)
            }
        }
    }

    @MainActor
    func testPreviousWithoutProgressDoesNotGuessOrSendCommand() async {
        for progress in [nil, -1] as [Int?] {
            let (model, fixture) = makeModel(progressMS: progress)
            await model.performWidgetAction(.previous)
            XCTAssertTrue(fixture.commands.isEmpty)
            XCTAssertEqual(model.actionError, PlaybackServiceError.missingProgress.localizedDescription)
        }
    }

    @MainActor
    func testAppPreviousUsesFreshPositionInsteadOfLastPoll() async throws {
        let (model, fixture) = makeModel(progressMS: 1_000)
        await model.refresh()
        fixture.lock.withLock { fixture.progressMS = 40_000 }
        let finished = expectation(description: "App previous action finished")
        let observation = model.$isPerformingPlaybackAction.dropFirst().filter { !$0 }.sink { _ in
            finished.fulfill()
        }
        defer { observation.cancel() }
        model.previous()
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertEqual(fixture.commands.count, 1)
        XCTAssertEqual(fixture.commands.first?.url?.path, "/v1/me/player/seek")
        XCTAssertEqual(try playback(model).item?.title, "Song")
        XCTAssertEqual(fixture.reads, 3) // Initial poll, preflight, confirmation.
    }

    @MainActor
    func testRejectedRestartNeverFallsBackToSkippingTrack() async throws {
        let (model, fixture) = makeModel(commandStatus: 403, progressMS: 10_000)
        await model.performWidgetAction(.previous)
        XCTAssertEqual(fixture.commands.count, 1)
        XCTAssertEqual(fixture.commands.first?.url?.path, "/v1/me/player/seek")
        XCTAssertEqual(try playback(model).item?.title, "Song")
        XCTAssertNotNil(model.actionError)
    }

    @MainActor
    func testFailedActionPreservesPlaybackAndRateLimitStopsNewRequests() async throws {
        for status in [403, 404, 429] {
            let (model, fixture) = makeModel(commandStatus: status)
            await model.refresh()
            let previous = try playback(model)
            await model.performWidgetAction(.play)
            XCTAssertEqual(try playback(model).item, previous.item)
            XCTAssertFalse(try playback(model).isPlaying)
            XCTAssertNotNil(model.actionError)
            XCTAssertFalse(model.isPerformingPlaybackAction)
            if status == 429 {
                try await Task.sleep(for: .milliseconds(750))
                await model.performWidgetAction(.next)
                await model.refresh() // Polling must respect the same command cooldown.
                XCTAssertEqual(fixture.commands.count, 1)
                XCTAssertEqual(fixture.reads, 2)
            }
        }
    }

    @MainActor
    func testRateLimitedReadSuppressesPollingWithoutDiscardingPlayback() async throws {
        let (model, fixture) = makeModel()
        await model.refresh()
        let before = try playback(model)
        fixture.lock.withLock { fixture.readStatus = 429 }
        await model.refresh()
        await model.refresh()
        await model.performWidgetAction(.next)
        XCTAssertEqual(fixture.reads, 2)
        XCTAssertTrue(fixture.commands.isEmpty)
        XCTAssertEqual(try playback(model), before)
        XCTAssertNotNil(model.refreshError)
    }

    @MainActor
    func testDisconnectClearsPlaybackWithoutAppGroupStorage() async throws {
        let (model, _) = makeModel()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlaybackURLProtocol.self]
        let network = URLSession(configuration: configuration)
        defer { network.invalidateAndCancel() }
        let auth = SpotifyAuthService(configuration: .current, credentialStore: TestCredentialStore())
        let settings = SettingsViewModel(preferencesStore: TestPreferencesStore(), authService: auth,
                                        apiClient: SpotifyAPIClient(authService: auth, session: network))
        await settings.restoreSession()
        let publisher = WidgetSnapshotPublisher(store: nil)
        publisher.start(settings: settings, playback: model)
        await model.refresh()
        XCTAssertTrue(model.canControlPlayback)
        settings.disconnectSpotify()
        XCTAssertFalse(model.canControlPlayback)
        if case .idle = model.state {} else { XCTFail("Disconnected playback was retained") }
    }

    @MainActor
    func testNoActiveDeviceDoesNotSendCommand() async throws {
        let (model, fixture) = makeModel(active: false)
        await model.performWidgetAction(.next)
        XCTAssertTrue(fixture.commands.isEmpty)
        XCTAssertEqual(model.actionError, SpotifyAPIError.notFound.localizedDescription)
        XCTAssertNotNil(try playback(model).item)
    }

    @MainActor
    func testFailedConfirmationKeepsMetadataAndReportsError() async throws {
        let (model, _) = makeModel(failConfirmation: true)
        await model.performWidgetAction(.pause)
        XCTAssertNotNil(try playback(model).item)
        XCTAssertNotNil(model.actionError)
        XCTAssertFalse(model.isPerformingPlaybackAction)
    }

    func testOldSnapshotsDecodeAndRepeatChangesInvalidateTimeline() throws {
        let json = Data(#"{"item":null,"isPlaying":false,"progressAtFetch":0,"device":null,"fetchedAt":0}"#.utf8)
        var state = try JSONDecoder().decode(PlaybackState.self, from: json)
        XCTAssertNil(state.repeatMode)
        let previous = WidgetSnapshot(status: .paused, playback: state)
        state.repeatMode = .track
        var updated = WidgetSnapshot(status: .paused, playback: state)
        let now = Date()
        XCTAssertTrue(updated.needsReload(comparedTo: previous, at: now, lastReload: now))
        updated.interaction = .performing(until: now.addingTimeInterval(10))
        XCTAssertTrue(updated.isPerformingAction(at: now))
        XCTAssertFalse(updated.isPerformingAction(at: now.addingTimeInterval(11)))
        XCTAssertEqual(try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(updated)), updated)
    }

    @MainActor
    func testEmptyResponsesRetainConfirmedItemAndFreezeProgress() async throws {
        let (model, fixture) = makeModel(progressMS: 12_345, isPlaying: true)
        await model.refresh()
        let before = try playback(model)
        fixture.lock.withLock { fixture.readStatus = 204 }
        await model.refresh()
        let saved = try playback(model)
        XCTAssertTrue(saved.isLastKnown)
        XCTAssertEqual(saved.item, before.item)
        XCTAssertEqual(saved.progress(at: Date().addingTimeInterval(300)), 12.345)
        XCTAssertEqual(saved.fetchedAt, before.fetchedAt)
        XCTAssertFalse(saved.isPlaying)
        XCTAssertNil(saved.device) // Never present an old device as currently active.
        XCTAssertTrue(model.canControlPlayback)
        await model.refresh()
        XCTAssertEqual(try playback(model), saved)
        fixture.lock.withLock { fixture.readStatus = 200; fixture.hasItem = false }
        await model.refresh()
        XCTAssertEqual(try playback(model), saved)
        fixture.lock.withLock { fixture.hasItem = true; fixture.title = "New live song" }
        await model.refresh()
        XCTAssertFalse(try playback(model).isLastKnown)
        XCTAssertEqual(try playback(model).item?.title, "New live song")
    }

    @MainActor
    func testEmptyWithoutHistoryAndDisconnectDoNotResurrectMetadata() async throws {
        let (model, fixture) = makeModel()
        fixture.lock.withLock { fixture.readStatus = 204 }
        await model.refresh()
        guard case .nothingPlaying = model.state else { return XCTFail("No history must stay empty") }
        fixture.lock.withLock { fixture.readStatus = 200 }
        await model.refresh()
        XCTAssertNotNil(try playback(model).item)
        model.invalidateSessionPlayback()
        fixture.lock.withLock { fixture.readStatus = 204 }
        await model.refresh()
        guard case .nothingPlaying = model.state else { return XCTFail("Disconnect must forget history") }
    }

    @MainActor
    func testSavedPlaybackSurvivesNetworkFailureAndCommandFailure() async throws {
        let (model, fixture) = makeModel(commandStatus: 404)
        await model.refresh()
        fixture.lock.withLock { fixture.readStatus = 204 }
        await model.refresh()
        let saved = try playback(model)
        fixture.lock.withLock { fixture.failReads = true }
        await model.refresh()
        XCTAssertEqual(try playback(model), saved)
        XCTAssertNotNil(model.refreshError)
        fixture.lock.withLock { fixture.failReads = false }
        await model.performWidgetAction(.play)
        XCTAssertEqual(fixture.commands.count, 1)
        XCTAssertEqual(try playback(model), saved)
        XCTAssertEqual(model.actionError, SpotifyAPIError.notFound.localizedDescription)
    }

    @MainActor
    func testSavedPlayResumesExistingSessionWithoutReplacingQueue() async throws {
        let (model, fixture) = makeModel()
        await model.refresh()
        fixture.lock.withLock { fixture.readStatus = 204 }
        await model.refresh()
        await model.performWidgetAction(.play)
        XCTAssertEqual(fixture.commands.count, 1)
        XCTAssertEqual(fixture.commands.first?.url?.path, "/v1/me/player/play")
        XCTAssertEqual(fixture.commandBodies.first, Data()) // No URI override for an unreported session.
        XCTAssertTrue(try playback(model).isPlaying)
        XCTAssertFalse(try playback(model).isLastKnown)
    }

    @MainActor
    func testAppPlayFromHistoryNeverPausesNewPlaybackOrReplacesItsItem() async throws {
        let (model, fixture) = makeModel()
        await model.refresh()
        fixture.lock.withLock { fixture.readStatus = 204 }
        await model.refresh()
        fixture.lock.withLock {
            fixture.readStatus = 200
            fixture.title = "Song chosen elsewhere"
            fixture.isPlaying = true
        }
        let finished = expectation(description: "App play finished")
        let observation = model.$isPerformingPlaybackAction.dropFirst().filter { !$0 }.sink { _ in finished.fulfill() }
        defer { observation.cancel() }
        model.togglePlayPause()
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertEqual(fixture.commands.count, 1)
        XCTAssertEqual(fixture.commands.first?.url?.path, "/v1/me/player/play")
        XCTAssertEqual(fixture.commandBodies.first, Data())
        XCTAssertEqual(try playback(model).item?.title, "Song chosen elsewhere")
        XCTAssertTrue(try playback(model).isPlaying)
    }

    @MainActor
    func testMissingContextOnActiveDeviceRestoresSavedURIAndPosition() async throws {
        let (model, fixture) = makeModel(progressMS: 12_345)
        await model.refresh()
        fixture.lock.withLock { fixture.hasItem = false }
        await model.refresh()
        await model.performWidgetAction(.play)
        let body = try XCTUnwrap(fixture.commandBodies.first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["uris"] as? [String], [PlaybackFixture.trackURI])
        XCTAssertEqual(json["position_ms"] as? Int, 12_345)
        XCTAssertEqual(fixture.commands.first?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(fixture.commands.count, 1)
        XCTAssertTrue(try playback(model).isPlaying)
        XCTAssertNil(model.actionError)
    }

    @MainActor
    func testSavedNextAndPreviousRequireRealPlayback() async throws {
        for action in [PlaybackAction.previous, .next] {
            let (model, fixture) = makeModel()
            await model.refresh()
            fixture.lock.withLock { fixture.readStatus = 204 }
            await model.refresh()
            await model.performWidgetAction(action)
            XCTAssertTrue(fixture.commands.isEmpty)
            XCTAssertTrue(try playback(model).isLastKnown)
            XCTAssertEqual(model.actionError, SpotifyAPIError.notFound.localizedDescription)
        }
    }

    @MainActor
    func testSnapshotRoundTripRestoresOnlyForSameAccountAndClearsOnDisconnect() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSharedStore(directory: directory)
        let (model, fixture) = makeModel(isPlaying: true)
        await model.refresh()
        let state = try playback(model)
        try store.write(WidgetSnapshot(status: .playing, playback: state, accountID: "account-a"))
        let snapshot = try XCTUnwrap(store.read())
        XCTAssertNil(snapshot.rememberedPlayback(for: "account-b"))
        XCTAssertNil(snapshot.rememberedPlayback(for: nil))
        let saved = try XCTUnwrap(snapshot.rememberedPlayback(for: "account-a"))
        model.invalidateSessionPlayback()
        model.restoreLastPlayback(saved)
        fixture.lock.withLock { fixture.readStatus = 204 }
        await model.refresh()
        XCTAssertEqual(try playback(model).item, state.item)
        XCTAssertFalse(try playback(model).isPlaying)
        XCTAssertTrue(try playback(model).isLastKnown)
        let next = WidgetSnapshot(status: .paused, playback: saved, accountID: "account-a")
        XCTAssertNil(next.freshnessDeadline)
        XCTAssertTrue(next.needsReload(comparedTo: snapshot, at: Date(), lastReload: Date()))
        try store.write(WidgetSnapshot()) // Same operation as publisher on Disconnect.
        XCTAssertNil(try store.read()?.rememberedPlayback(for: "account-a"))
    }

    @MainActor
    func testPublisherRestoresCachedStateAndDisconnectClearsAppAndStore() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSharedStore(directory: directory)
        let (seed, fixture) = makeModel()
        await seed.refresh()
        try store.write(WidgetSnapshot(status: .paused, playback: try playback(seed), accountID: "account-a"))
        fixture.lock.withLock { fixture.readStatus = 204 }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlaybackURLProtocol.self]
        let auth = SpotifyAuthService(configuration: .current, credentialStore: TestCredentialStore())
        let client = SpotifyAPIClient(authService: auth, session: URLSession(configuration: configuration))
        let settings = SettingsViewModel(preferencesStore: TestPreferencesStore(), authService: auth, apiClient: client)
        await settings.restoreSession()
        let publisher = WidgetSnapshotPublisher(store: store)
        let model = PlaybackViewModel(service: SpotifyPlaybackService(apiClient: client), onPlaybackUpdate: publisher.publish)
        publisher.start(settings: settings, playback: model)
        await model.refresh()
        XCTAssertTrue(try playback(model).isLastKnown)
        XCTAssertTrue(try store.read()?.playback?.isLastKnown == true)
        let disconnected = expectation(description: "Disconnected")
        let observation = settings.$authenticationState.dropFirst().sink { state in
            if case .disconnected = state { disconnected.fulfill() }
        }
        defer { observation.cancel() }
        settings.disconnectSpotify()
        await fulfillment(of: [disconnected], timeout: 3)
        XCTAssertNil(try store.read()?.playback)
        XCTAssertNil(try store.read()?.accountID)
        XCTAssertFalse(model.canControlPlayback)
        publisher.publish(try playback(seed)) // A late callback must not restore cleared data.
        XCTAssertNil(try store.read()?.playback)
    }

    @MainActor
    func testRestorationRejectsMissingURIAndNeverFallsBackAfter403Or429() async throws {
        let (model, fixture) = makeModel()
        await model.refresh()
        let state = try playback(model)
        let unsupported = PlaybackItem(id: nil, title: "Local item", artists: [], albumName: nil,
                                       artworkURL: nil, duration: 10, type: .unknown)
        model.restoreLastPlayback(PlaybackState(item: unsupported, isPlaying: false, progressAtFetch: 3,
                                                device: nil, fetchedAt: Date()))
        fixture.lock.withLock { fixture.hasItem = false }
        await model.performWidgetAction(.play)
        XCTAssertTrue(fixture.commands.isEmpty)
        XCTAssertEqual(model.actionError, PlaybackServiceError.cannotRestoreItem.localizedDescription)
        for status in [403, 429] {
            let (denied, server) = makeModel(commandStatus: status)
            denied.restoreLastPlayback(state)
            server.lock.withLock { server.readStatus = 204 }
            await denied.performWidgetAction(.play)
            XCTAssertEqual(server.commands.count, 1)
            XCTAssertEqual(server.commandBodies.first, Data())
            XCTAssertTrue(try playback(denied).isLastKnown)
            XCTAssertNotNil(denied.actionError)
        }
    }

    @MainActor
    private func makeModel(commandStatus: Int = 204, active: Bool = true, failConfirmation: Bool = false,
                           progressMS: Int? = 1_000, isPlaying: Bool = false) -> (PlaybackViewModel, PlaybackFixture) {
        let fixture = PlaybackFixture(commandStatus: commandStatus, active: active, failConfirmation: failConfirmation,
                                       progressMS: progressMS, isPlaying: isPlaying)
        PlaybackURLProtocol.fixture = fixture
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlaybackURLProtocol.self]
        let auth = SpotifyAuthService(configuration: .current, credentialStore: TestCredentialStore())
        let client = SpotifyAPIClient(authService: auth, session: URLSession(configuration: configuration))
        return (PlaybackViewModel(service: SpotifyPlaybackService(apiClient: client)), fixture)
    }

    @MainActor
    private func playback(_ model: PlaybackViewModel) throws -> PlaybackState {
        switch model.state {
        case .playing(let state), .paused(let state), .lastPlayed(let state): return state
        default: throw NSError(domain: "Expected visible playback", code: 1)
        }
    }
}

private final class TestCredentialStore: CredentialStore {
    func readSession() -> SpotifySession? {
        SpotifySession(accessToken: "test-only", refreshToken: "test-only", expiresAt: .distantFuture, scope: "")
    }
    func save(_ session: SpotifySession) {}
    func deleteSession() {}
}

private struct TestPreferencesStore: PreferencesStore {
    func load() -> WidgetPreferences { WidgetPreferences() }
    func save(_ preferences: WidgetPreferences) {}
}

private final class PlaybackFixture: @unchecked Sendable {
    static let trackURI = "spotify:track:4iV5W9uYEdYUVa79Axb7Rh"
    let lock = NSLock()
    let commandStatus: Int
    let active: Bool
    let failConfirmation: Bool
    var commands: [URLRequest] = []
    var commandBodies: [Data] = []
    var readStatus = 200
    var hasItem = true
    var failReads = false
    var reads = 0
    var isPlaying: Bool
    var progressMS: Int?
    var title = "Song"
    var repeatMode = "off"

    init(commandStatus: Int, active: Bool, failConfirmation: Bool, progressMS: Int?, isPlaying: Bool) {
        self.commandStatus = commandStatus
        self.active = active
        self.failConfirmation = failConfirmation
        self.progressMS = progressMS
        self.isPlaying = isPlaying
    }

    func reply(_ request: URLRequest) throws -> (Int, Data) {
        lock.lock()
        defer { lock.unlock() }
        if request.url?.path == "/v1/me" {
            return (200, Data(#"{"id":"account-a","display_name":"Test account"}"#.utf8))
        }
        if request.httpMethod == "GET" {
            let types = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "additional_types" }?.value
            XCTAssertEqual(types, "track,episode", "Both playback endpoints must opt into episodes")
            reads += 1
            if failReads { throw URLError(.notConnectedToInternet) }
            if failConfirmation, !commands.isEmpty { throw URLError(.notConnectedToInternet) }
            if readStatus != 200 { return (readStatus, Data()) }
            return (200, try JSONSerialization.data(withJSONObject: [
                "is_playing": isPlaying, "progress_ms": progressMS as Any? ?? NSNull(), "repeat_state": repeatMode,
                "device": ["name": "Test Mac", "type": "Computer", "is_active": active],
                "item": hasItem ? ["type": "track", "id": title, "uri": Self.trackURI, "name": title, "duration_ms": 180000,
                         "artists": [["name": "Artist"]]] as Any : NSNull()
            ]))
        }
        commands.append(request)
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        commandBodies.append(body)
        if commandStatus == 204 {
            switch request.url?.lastPathComponent {
            case "play": isPlaying = true; readStatus = 200; hasItem = true
            case "pause": isPlaying = false
            case "previous": title = "Previous song"; progressMS = 0
            case "next": title = "Next song"
            case "seek": progressMS = 0
            case "repeat": repeatMode = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value ?? "off"
            default: break
            }
        }
        return (commandStatus, Data())
    }
}

private final class PlaybackURLProtocol: URLProtocol, @unchecked Sendable {
    static var fixture: PlaybackFixture?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.fixture!.reply(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Retry-After": "60"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
