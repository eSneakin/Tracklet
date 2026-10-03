import Foundation

@MainActor
final class PlaybackViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case playing(PlaybackState)
        case paused(PlaybackState)
        case lastPlayed(PlaybackState)
        case nothingPlaying
        case error(String)

        /// Visible content is independent of an in-flight refresh or command.
        var playback: PlaybackState? {
            switch self {
            case .playing(let playback), .paused(let playback), .lastPlayed(let playback): playback
            case .idle, .loading, .nothingPlaying, .error: nil
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var isRefreshing = false
    @Published private(set) var isPerformingPlaybackAction = false
    @Published private(set) var actionError: String?
    @Published private(set) var refreshError: String?
    private let service: SpotifyPlaybackService
    private var pollingTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var actionRetryDate = Date.distantPast
    private let pollInterval: Duration = .seconds(30)
    private var sessionGeneration = 0
    private var lastConfirmedPlayback: PlaybackState?
    private let onPlaybackUpdate: (PlaybackState?) -> Void
    private let onPlaybackFailure: () -> Void
    private let artworkLookup: (PlaybackState) -> URL?

    init(service: SpotifyPlaybackService, onPlaybackUpdate: @escaping (PlaybackState?) -> Void = { _ in }, onPlaybackFailure: @escaping () -> Void = {}, artworkLookup: @escaping (PlaybackState) -> URL? = { _ in nil }) {
        self.service = service
        self.onPlaybackUpdate = onPlaybackUpdate
        self.onPlaybackFailure = onPlaybackFailure
        self.artworkLookup = artworkLookup
    }

    func invalidateSessionPlayback() {
        sessionGeneration += 1
        // A new account must not join the previous account's suspended refresh.
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
        lastConfirmedPlayback = nil
        actionRetryDate = .distantPast
        state = .idle
        actionError = nil
        refreshError = nil
    }

    func restoreLastPlayback(_ playback: PlaybackState) {
        guard playback.item != nil else { return }
        accept(playback.remembered())
    }

    func refresh(afterAction: Bool = false) async {
        guard !isPerformingPlaybackAction || afterAction else { return }
        if let refreshTask { await refreshTask.value; return }
        let generation = sessionGeneration
        let task = Task {
            defer { if generation == sessionGeneration { refreshTask = nil } }
            await fetchPlayback(generation: generation)
        }
        refreshTask = task
        await task.value
    }

    private func fetchPlayback(generation: Int) async {
        guard generation == sessionGeneration, !Task.isCancelled else { return }
        let hasVisiblePlayback = state.playback != nil
        isRefreshing = true
        if !hasVisiblePlayback, case .idle = state { state = .loading }
        defer { if generation == sessionGeneration { isRefreshing = false } }
        do {
            refreshError = nil
            let result = try await service.fetchPlaybackState()
            guard generation == sessionGeneration else { return }
            accept(result)
        } catch {
            guard generation == sessionGeneration else { return }
            onPlaybackFailure()
            if case SpotifyAuthError.noSession = error {
                if !hasVisiblePlayback { state = .nothingPlaying }
            } else {
                refreshError = error.localizedDescription
                if !hasVisiblePlayback { state = .error(error.localizedDescription) }
            }
        }
    }

    func startPolling() async {
        await refresh()
        pollingTask?.cancel()
        let interval = pollInterval
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                await self.refresh()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func previous() { Task { await perform(.previous) } }
    func next() { Task { await perform(.next) } }

    func togglePlayPause() {
        guard canControlPlayback else { return }
        let action: PlaybackAction
        if case .playing = state { action = .pause } else { action = .play }
        Task { await perform(action) }
    }

    func performWidgetAction(_ action: PlaybackAction) async {
        await perform(action, revalidateDevice: true)
    }

    private func perform(_ action: PlaybackAction, revalidateDevice: Bool = false) async {
        guard !isPerformingPlaybackAction, Date() >= actionRetryDate else { return }
        guard revalidateDevice || canControlPlayback else { return }
        isPerformingPlaybackAction = true
        actionError = nil
        let generation = sessionGeneration
        var rollback: State?
        var commandSucceeded = false
        defer {
            isPerformingPlaybackAction = false
            actionRetryDate = max(actionRetryDate, Date().addingTimeInterval(0.7))
        }
        do {
            // Finish any older poll before issuing a command; it must not overwrite its result.
            await refreshTask?.value
            guard generation == sessionGeneration else { return }
            let current = try await service.fetchPlaybackState()
            guard generation == sessionGeneration else { return }
            accept(current)
            let hasCurrentItem = current?.item != nil
            let saved = lastConfirmedPlayback
            if action != .play || hasCurrentItem {
                guard hasCurrentItem, current?.device?.isActive == true else { throw SpotifyAPIError.notFound }
            } else {
                guard saved?.item != nil else { throw SpotifyAPIError.notFound }
                if let current, current.device?.isActive != true { throw SpotifyAPIError.notFound }
            }
            if hasCurrentItem, action == .play || action == .pause {
                rollback = state
                state = optimisticPlayback(isPlaying: action == .play)
            }
            if action == .play, !hasCurrentItem, current?.device?.isActive == true, let saved {
                try await service.restore(saved)
            } else {
                // A 204 read can hide Spotify's resumable session. Try Play once, never auto-transfer.
                try await service.perform(action, playback: current)
            }
            commandSucceeded = true
            try await Task.sleep(for: .milliseconds(500))
            guard generation == sessionGeneration else { return }
            await refresh(afterAction: true)
            // The command may succeed while confirmation fails. Keep the last state visible.
            actionError = refreshError
            if actionError == nil, case .lastPlayed = state {
                actionError = "Playback not confirmed. Open Spotify to continue."
            }
        } catch {
            guard generation == sessionGeneration else { return }
            if !commandSucceeded, let rollback { state = rollback }
            if case SpotifyAPIError.rateLimited(let delay) = error {
                actionRetryDate = Date().addingTimeInterval(max(1, delay ?? 30))
            }
            actionError = error.localizedDescription
        }
    }

    private func accept(_ playback: PlaybackState?) {
        if let playback, playback.item != nil {
            lastConfirmedPlayback = playback
        } else {
            lastConfirmedPlayback = lastConfirmedPlayback?.remembered()
        }
        guard let visible = lastConfirmedPlayback else {
            state = .nothingPlaying
            onPlaybackUpdate(nil)
            return
        }
        state = visible.isLastKnown ? .lastPlayed(visible) : (visible.isPlaying ? .playing(visible) : .paused(visible))
        onPlaybackUpdate(visible)
    }

    var isLoading: Bool { if case .loading = state { return true }; return false }

    var cachedArtworkURL: URL? { lastConfirmedPlayback.flatMap(artworkLookup) }

    private func optimisticPlayback(isPlaying: Bool) -> State {
        switch state {
        case .playing(let playback), .paused(let playback):
            return .pausedOrPlaying(playback, isPlaying: isPlaying)
        default:
            // History is not evidence of a live device; wait for Spotify confirmation.
            return state
        }
    }

    var canControlPlayback: Bool {
        state.playback?.item != nil
    }
}

private extension PlaybackViewModel.State {
    static func pausedOrPlaying(_ playback: PlaybackState, isPlaying: Bool) -> Self {
        let now = Date()
        let optimistic = PlaybackState(
            item: playback.item,
            isPlaying: isPlaying,
            progressAtFetch: playback.progress(at: now),
            device: playback.device,
            fetchedAt: now,
            repeatMode: playback.repeatMode
        )
        return isPlaying ? .playing(optimistic) : .paused(optimistic)
    }
}
