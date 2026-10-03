import Combine
import XCTest
@testable import Tracklet

final class AuthenticationTests: XCTestCase {
    @MainActor
    func testConcurrentRefreshesShareRequestAndPersistRotationOnce() async throws {
        let store = AuthenticationMemoryStore(expired: true)
        let requested = expectation(description: "One token request")
        requested.assertForOverFulfill = true
        var pending: AuthenticationURLProtocol?
        var requestCount = 0
        let network = makeNetwork { request in
            requestCount += 1
            pending = request
            requested.fulfill()
        }
        defer { network.invalidateAndCancel() }
        let auth = makeAuth(store, network: network)
        let started = expectation(description: "All callers started")
        started.expectedFulfillmentCount = 10
        let callers = (0..<10).map { index in
            Task { @MainActor in
                started.fulfill()
                return try await (index.isMultiple(of: 2) ? auth.validAccessToken() : auth.refreshAccessToken())
            }
        }
        await fulfillment(of: [started, requested], timeout: 3)
        try XCTUnwrap(pending).respond(Self.tokenResponse)
        for caller in callers {
            let token = try await caller.value
            XCTAssertEqual(token, "new-access")
        }
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(store.saveCount, 1)
        XCTAssertEqual(store.session?.refreshToken, "new-refresh")
        XCTAssertEqual(store.session?.scope, "original-scope")
        let token = try await auth.refreshAccessToken(rejectedToken: "old-access")
        XCTAssertEqual(token, "new-access")
        XCTAssertEqual(requestCount, 1, "A late 401 must reuse the replacement token")
    }

    @MainActor
    func testCancellingOneRefreshWaiterDoesNotCancelOtherWaiters() async throws {
        let store = AuthenticationMemoryStore(expired: true)
        let requested = expectation(description: "Refresh pending")
        var pending: AuthenticationURLProtocol?
        let network = makeNetwork { pending = $0; requested.fulfill() }
        defer { network.invalidateAndCancel() }
        let auth = makeAuth(store, network: network)
        let first = Task { try await auth.validAccessToken() }
        await fulfillment(of: [requested], timeout: 3)
        let secondStarted = expectation(description: "Second waiter started")
        let second = Task {
            secondStarted.fulfill()
            return try await auth.validAccessToken()
        }
        await fulfillment(of: [secondStarted], timeout: 3)
        first.cancel()
        try XCTUnwrap(pending).respond(Self.tokenResponse)
        do { _ = try await first.value; XCTFail("Cancelled waiter returned a token") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let token = try await second.value
        XCTAssertEqual(token, "new-access")
        XCTAssertEqual(store.saveCount, 1)
    }

    @MainActor
    func testDisconnectCancelsRefreshAndCannotReloadAfterFailedDeletion() async throws {
        let store = AuthenticationMemoryStore(expired: true)
        store.deleteError = CredentialStoreError.keychain(-1)
        let requested = expectation(description: "Refresh pending")
        let network = makeNetwork { _ in requested.fulfill() }
        defer { network.invalidateAndCancel() }
        let auth = makeAuth(store, network: network)
        let refresh = Task { try await auth.validAccessToken() }
        await fulfillment(of: [requested], timeout: 3)
        XCTAssertThrowsError(try auth.disconnect())
        do { _ = try await refresh.value; XCTFail("Disconnected refresh returned a token") } catch {}
        XCTAssertEqual(store.saveCount, 0)
        XCTAssertNil(try auth.restoreSession())
        do { _ = try await auth.validAccessToken(); XCTFail("Disconnected credentials were reloaded") }
        catch SpotifyAuthError.noSession {} catch { XCTFail("Unexpected error: \(error)") }
    }

    @MainActor
    func testDisconnectRejectsLateAuthorizationCallback() async throws {
        let store = AuthenticationMemoryStore(expired: false)
        let opened = expectation(description: "Authorization opened")
        var callback: URL?
        var continuation: CheckedContinuation<URL, Error>?
        let network = makeNetwork { _ in XCTFail("A stale callback must not exchange its code") }
        defer { network.invalidateAndCancel() }
        let auth = makeAuth(store, network: network) { url in
            callback = Self.callback(for: url)
            return try await withCheckedThrowingContinuation {
                continuation = $0
                opened.fulfill()
            }
        }
        let login = Task { try await auth.authorize() }
        await fulfillment(of: [opened], timeout: 3)
        try auth.disconnect()
        try XCTUnwrap(continuation).resume(returning: XCTUnwrap(callback))
        do { _ = try await login.value; XCTFail("Late login succeeded") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertNil(store.session)
        XCTAssertEqual(store.saveCount, 0)
    }

    @MainActor
    func testDisconnectRejectsLateAuthorizationExchange() async throws {
        let store = AuthenticationMemoryStore(expired: false)
        let requested = expectation(description: "Exchange pending")
        var pending: AuthenticationURLProtocol?
        let network = makeNetwork { pending = $0; requested.fulfill() }
        defer { network.invalidateAndCancel() }
        let auth = makeAuth(store, network: network, authorizationHandler: { Self.callback(for: $0) })
        let login = Task { try await auth.authorize() }
        await fulfillment(of: [requested], timeout: 3)
        try auth.disconnect()
        try XCTUnwrap(pending).respond(Self.tokenResponse)
        do { _ = try await login.value; XCTFail("Late exchange succeeded") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertNil(store.session)
        XCTAssertEqual(store.saveCount, 0)
    }

    @MainActor
    func testInvalidCallbacksNeverExchangeCode() async throws {
        let store = AuthenticationMemoryStore(expired: false)
        let network = makeNetwork { _ in XCTFail("Invalid callback reached token endpoint") }
        defer { network.invalidateAndCancel() }
        for invalid in ["tracklet://wrong", "tracklet://callback?state=wrong", "tracklet://callback?state=duplicate"] {
            let auth = makeAuth(store, network: network) { url in
                let valid = URLComponents(url: Self.callback(for: url), resolvingAgainstBaseURL: false)!
                var callback = URLComponents(string: invalid)!
                callback.queryItems = (callback.queryItems ?? []) + (valid.queryItems ?? [])
                return callback.url!
            }
            do { _ = try await auth.authorize(); XCTFail("Invalid callback accepted") } catch {}
        }
        XCTAssertEqual(store.saveCount, 0)
    }

    @MainActor
    func testRefreshFailureCanRetryAndKeepsOmittedRefreshToken() async throws {
        let store = AuthenticationMemoryStore(expired: true)
        var requests = 0
        let network = makeNetwork { request in
            requests += 1
            if requests == 1 { request.respond("{}", status: 503) }
            else { request.respond(#"{"access_token":"new-access","token_type":"Bearer","expires_in":3600}"#) }
        }
        defer { network.invalidateAndCancel() }
        let auth = makeAuth(store, network: network)
        do { _ = try await auth.validAccessToken(); XCTFail("503 accepted") }
        catch SpotifyAuthError.tokenRequestFailed(503) {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(store.session?.accessToken, "old-access")
        let token = try await auth.validAccessToken()
        XCTAssertEqual(token, "new-access")
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(store.session?.refreshToken, "old-refresh")
        XCTAssertEqual(store.session?.scope, "original-scope")
    }

    @MainActor
    func testStartupNetworkAndServerFailuresRetainCredentialsAndAllowRetry() async throws {
        for expired in [false, true] {
            for failure in [0, 503] {
                let store = AuthenticationMemoryStore(expired: expired)
                let original = store.session
                var failing = true
                let network = makeNetwork { request in
                    if failing {
                        if failure == 0 { request.fail(URLError(.notConnectedToInternet)) }
                        else { request.respond("{}", status: failure) }
                    } else if request.request.url?.path == "/api/token" {
                        request.respond(Self.tokenResponse)
                    } else {
                        request.respond(Self.userResponse)
                    }
                }
                defer { network.invalidateAndCancel() }
                let auth = makeAuth(store, network: network)
                let settings = makeSettings(auth, network: network)
                await settings.restoreSession()
                XCTAssertNotNil(settings.errorMessage)
                XCTAssertEqual(store.session, original)
                XCTAssertEqual(store.deleteCount, 0)
                failing = false
                await settings.restoreSession()
                XCTAssertEqual(settings.account?.id, "test-account")
                XCTAssertNil(settings.errorMessage)
            }
        }
    }

    @MainActor
    func testNewPlaybackSessionDoesNotJoinObsoleteRefresh() async throws {
        let requested = expectation(description: "Old account request pending")
        var reads = 0
        let network = makeNetwork { request in
            reads += 1
            if reads == 1 { requested.fulfill() }
            else { request.respond(Self.playbackResponse) }
        }
        defer { network.invalidateAndCancel() }
        let auth = makeAuth(AuthenticationMemoryStore(expired: false), network: network)
        let model = PlaybackViewModel(service: SpotifyPlaybackService(apiClient: SpotifyAPIClient(authService: auth, session: network)))
        let oldRefresh = Task { await model.refresh() }
        await fulfillment(of: [requested], timeout: 3)
        model.invalidateSessionPlayback()
        await model.refresh()
        await oldRefresh.value
        XCTAssertEqual(reads, 2)
        guard case .playing(let playback) = model.state else { return XCTFail("New session was not fetched") }
        XCTAssertEqual(playback.item?.title, "New song")
        XCTAssertFalse(model.isRefreshing)
    }

    @MainActor
    func testSlowRefreshKeepsPlayingContentAndTemporaryFailureKeepsProgress() async throws {
        let requested = expectation(description: "Background refresh pending")
        var pending: AuthenticationURLProtocol?
        var reads = 0
        let network = makeNetwork { request in
            reads += 1
            if reads == 1 { request.respond(Self.playbackResponse) }
            else { pending = request; requested.fulfill() }
        }
        defer { network.invalidateAndCancel() }
        let auth = makeAuth(AuthenticationMemoryStore(expired: false), network: network)
        let model = PlaybackViewModel(service: SpotifyPlaybackService(apiClient: SpotifyAPIClient(authService: auth, session: network)))
        await model.refresh()
        let refresh = Task { await model.refresh() }
        await fulfillment(of: [requested], timeout: 3)
        XCTAssertTrue(model.isRefreshing)
        XCTAssertFalse(model.isLoading)
        guard case .playing(let before) = model.state else { return XCTFail("Refresh removed content") }
        XCTAssertEqual(before.progress(at: before.fetchedAt.addingTimeInterval(3)), 4)
        try XCTUnwrap(pending).fail(URLError(.notConnectedToInternet))
        await refresh.value
        guard case .playing(let after) = model.state else { return XCTFail("Error removed content") }
        XCTAssertEqual(after, before)
        XCTAssertNotNil(model.refreshError)
    }

    @MainActor
    func testDisconnectRejectsLateStartupProfile() async throws {
        let store = AuthenticationMemoryStore(expired: false)
        let requested = expectation(description: "Profile pending")
        var pending: AuthenticationURLProtocol?
        let network = makeNetwork { pending = $0; requested.fulfill() }
        defer { network.invalidateAndCancel() }
        let auth = makeAuth(store, network: network)
        let settings = makeSettings(auth, network: network)
        let startup = Task { await settings.restoreSession() }
        await fulfillment(of: [requested], timeout: 3)
        settings.disconnectSpotify()
        try XCTUnwrap(pending).respond(Self.userResponse)
        await startup.value
        XCTAssertEqual(settings.authenticationState, .disconnected)
        XCTAssertNil(store.session)
    }

    @MainActor
    func testImmediateDisconnectPreventsQueuedLoginAndReportsDeletionFailure() async {
        let store = AuthenticationMemoryStore(expired: false)
        let network = makeNetwork { _ in XCTFail("Disconnected login reached network") }
        defer { network.invalidateAndCancel() }
        let auth = makeAuth(store, network: network) { _ in
            XCTFail("Disconnected login opened browser")
            throw CancellationError()
        }
        let settings = makeSettings(auth, network: network)
        settings.connectSpotify()
        settings.disconnectSpotify()
        await Task.yield()
        XCTAssertEqual(settings.authenticationState, .disconnected)
        XCTAssertNil(store.session)
        store.deleteError = CredentialStoreError.keychain(-1)
        settings.disconnectSpotify()
        XCTAssertNotNil(settings.errorMessage)
    }

    func testTokenValidationAndSessionRefreshMargin() throws {
        for response in [
            #"{"access_token":"","token_type":"Bearer","expires_in":3600}"#,
            #"{"access_token":"fake","token_type":"Basic","expires_in":3600}"#,
            #"{"access_token":"fake","token_type":"Bearer","expires_in":0}"#,
            #"{"access_token":"fake","token_type":"Bearer","expires_in":3600,"refresh_token":""}"#
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(SpotifyTokenResponse.self, from: Data(response.utf8)))
        }
        let token = try JSONDecoder().decode(SpotifyTokenResponse.self, from: Data(Self.tokenResponse.utf8))
        XCTAssertEqual(token.scope, "")
        XCTAssertTrue(SpotifySession(accessToken: "fake", refreshToken: "fake", expiresAt: Date().addingTimeInterval(30), scope: "").needsRefresh)
        XCTAssertTrue(SpotifySession(accessToken: "", refreshToken: "fake", expiresAt: .distantFuture, scope: "").needsRefresh)
        XCTAssertFalse(SpotifySession(accessToken: "fake", refreshToken: "fake", expiresAt: .distantFuture, scope: "").needsRefresh)
    }

    @MainActor
    private func makeAuth(_ store: AuthenticationMemoryStore, network: URLSession,
                          authorizationHandler: ((URL) async throws -> URL)? = nil) -> SpotifyAuthService {
        SpotifyAuthService(configuration: SpotifyConfiguration(clientID: "test-client", redirectURI: URL(string: "tracklet://callback")!),
                           credentialStore: store, urlSession: network, authorizationHandler: authorizationHandler)
    }

    @MainActor
    private func makeSettings(_ auth: SpotifyAuthService, network: URLSession) -> SettingsViewModel {
        SettingsViewModel(preferencesStore: AuthenticationPreferencesStore(), authService: auth,
                          apiClient: SpotifyAPIClient(authService: auth, session: network))
    }

    @MainActor
    private func makeNetwork(_ handler: @escaping @MainActor (AuthenticationURLProtocol) -> Void) -> URLSession {
        AuthenticationURLProtocol.lock.withLock { AuthenticationURLProtocol.handler = handler }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthenticationURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static let tokenResponse = #"{"access_token":"new-access","token_type":"Bearer","expires_in":3600,"refresh_token":"new-refresh"}"#
    private static let userResponse = #"{"id":"test-account","display_name":"Test account"}"#
    private static let playbackResponse = #"{"is_playing":true,"progress_ms":1000,"item":{"type":"track","name":"New song","duration_ms":180000,"artists":[]}}"#

    private static func callback(for authorizationURL: URL) -> URL {
        let state = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!
        var callback = URLComponents(string: "tracklet://callback")!
        callback.queryItems = [URLQueryItem(name: "state", value: state), URLQueryItem(name: "code", value: "test-code")]
        return callback.url!
    }
}

private final class AuthenticationMemoryStore: CredentialStore {
    var session: SpotifySession?
    var saveCount = 0
    var deleteCount = 0
    var deleteError: Error?

    init(expired: Bool) {
        session = SpotifySession(accessToken: "old-access", refreshToken: "old-refresh",
                                 expiresAt: expired ? .distantPast : .distantFuture, scope: "original-scope")
    }

    func readSession() -> SpotifySession? { session }
    func save(_ session: SpotifySession) { self.session = session; saveCount += 1 }
    func deleteSession() throws {
        deleteCount += 1
        if let deleteError { throw deleteError }
        session = nil
    }
}

private struct AuthenticationPreferencesStore: PreferencesStore {
    func load() -> WidgetPreferences { WidgetPreferences() }
    func save(_ preferences: WidgetPreferences) {}
}

private final class AuthenticationURLProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    static var handler: (@MainActor (AuthenticationURLProtocol) -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.lock.withLock({ Self.handler }) else {
            return fail(URLError(.unsupportedURL))
        }
        Task { @MainActor in handler(self) }
    }
    override func stopLoading() {}

    func respond(_ body: String, status: Int = 200) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    func fail(_ error: Error) { client?.urlProtocol(self, didFailWithError: error) }
}
