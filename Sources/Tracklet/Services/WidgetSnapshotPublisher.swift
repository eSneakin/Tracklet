import Combine
import CryptoKit
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers
import WidgetKit

@MainActor
final class WidgetSnapshotPublisher: ObservableObject {
    private let store: WidgetSharedStore?
    private var snapshot: WidgetSnapshot
    private var isConnected = false
    private var accountID: String?
    private var subscriptions = Set<AnyCancellable>()
    private var artworkTask: Task<Void, Never>?
    private var requestedArtworkURL: URL?
    private var lastReload = Date.distantPast
    private let logger = Logger(subsystem: "com.tracklet.app", category: "WidgetSharing")

    init(store: WidgetSharedStore?) {
        self.store = store
        snapshot = (try? store?.read()) ?? WidgetSnapshot()
    }

    /// Bind after session restoration so startup does not erase a valid cached snapshot.
    func start(settings: SettingsViewModel, playback: PlaybackViewModel) {
        guard subscriptions.isEmpty, store != nil else { return }
        settings.$preferences.sink { [weak self] preferences in
            guard let self else { return }
            var next = snapshot
            next.preferences = preferences
            commit(next)
        }.store(in: &subscriptions)
        playback.$isPerformingPlaybackAction.combineLatest(playback.$actionError).sink { [weak self] busy, error in
            guard let self, isConnected else { return }
            var next = snapshot
            if busy {
                if case .performing = next.interaction { return }
                next.interaction = .performing(until: Date().addingTimeInterval(90))
            } else {
                next.interaction = error.map(WidgetSnapshot.Interaction.failed)
            }
            commit(next)
        }.store(in: &subscriptions)
        settings.$authenticationState.removeDuplicates().sink { [weak self, weak playback] state in
            guard let self else { return }
            let connected: Bool
            let nextAccountID: String?
            switch state {
            case .connected(let account): connected = true; nextAccountID = account.id
            case .connecting: return
            case .disconnected, .error: connected = false; nextAccountID = nil
            }
            let changed = isConnected != connected || accountID != nextAccountID
            let remembered = connected ? snapshot.rememberedPlayback(for: nextAccountID) : nil
            isConnected = connected
            accountID = nextAccountID
            if !connected {
                artworkTask?.cancel()
                artworkTask = nil
                requestedArtworkURL = nil
                commit(WidgetSnapshot(preferences: snapshot.preferences))
            } else if changed, remembered == nil {
                commit(WidgetSnapshot(status: .loading, preferences: snapshot.preferences, accountID: accountID))
            }
            if changed {
                playback?.invalidateSessionPlayback()
                if let remembered { playback?.restoreLastPlayback(remembered) }
                if connected { Task { await playback?.refresh() } }
            }
        }.store(in: &subscriptions)
    }

    func publish(_ playback: PlaybackState?) {
        guard isConnected else { return }
        let url = playback?.item?.artworkURL
        let fileName = url.map { SHA256.hash(data: Data($0.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined() + ".jpg" }
        let cached = store?.artworkURL(fileName: fileName).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        let next = WidgetSnapshot(
            status: playback?.item == nil ? .nothingPlaying : (playback?.isPlaying == true ? .playing : .paused),
            playback: playback, preferences: snapshot.preferences, artworkFileName: cached ? fileName : nil,
            interaction: snapshot.interaction, accountID: accountID
        )
        commit(next)
        guard url != requestedArtworkURL || artworkTask == nil else { return }
        artworkTask?.cancel()
        requestedArtworkURL = url
        guard !cached, let url, url.scheme == "https", let fileName else { artworkTask = nil; return }
        artworkTask = Task { [weak self] in
            guard let self else { return }
            defer { if requestedArtworkURL == url { artworkTask = nil } }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      data.count <= 12 * 1_024 * 1_024, let jpeg = Self.thumbnail(data) else { return }
                try Task.checkCancellation()
                guard isConnected, snapshot.playback?.item?.artworkURL == url else { return }
                try store?.writeArtwork(jpeg, fileName: fileName)
                var updated = snapshot
                updated.artworkFileName = fileName
                commit(updated)
            } catch is CancellationError {
                return
            } catch {
                logger.error("Widget artwork unavailable; retaining metadata.")
            }
        }
    }

    func publishFailure() {
        guard isConnected, snapshot.playback == nil else { return }
        commit(WidgetSnapshot(status: .unavailable, preferences: snapshot.preferences, accountID: accountID))
    }

    func cachedArtworkURL(for playback: PlaybackState) -> URL? {
        guard playback.item?.artworkURL == snapshot.playback?.item?.artworkURL,
              let url = store?.artworkURL(fileName: snapshot.artworkFileName),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private func commit(_ next: WidgetSnapshot) {
        guard let store else { return }
        do {
            try store.write(next)
            let now = Date()
            if next.needsReload(comparedTo: snapshot, at: now, lastReload: lastReload) {
                WidgetCenter.shared.reloadTimelines(ofKind: TrackletWidgetIdentity.kind)
                lastReload = now
            }
            snapshot = next
        } catch {
            logger.error("Cannot publish widget snapshot. Check App Group and signing configuration.")
        }
    }

    private static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
