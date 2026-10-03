import Foundation

/// Shared source membership in the app and extension; no credentials or Spotify dependencies.
struct WidgetSharedStore {
    let directory: URL

    static func configured(bundle: Bundle = .main) -> Self? {
        guard let group = bundle.object(forInfoDictionaryKey: TrackletWidgetIdentity.appGroupInfoKey) as? String,
              !group.isEmpty, !group.contains("$("),
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        return Self(directory: container.appendingPathComponent("TrackletWidget", isDirectory: true))
    }

    func read() throws -> WidgetSnapshot? {
        let url = directory.appendingPathComponent("snapshot.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(WidgetSnapshot.self, from: Data(contentsOf: url))
    }

    func write(_ snapshot: WidgetSnapshot) throws {
        // The extension may read during publication; atomic replacement prevents partial JSON.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: directory.appendingPathComponent("snapshot.json"), options: .atomic)
    }

    func artworkURL(fileName: String?) -> URL? {
        // Snapshot data crosses a process boundary. Accept only hashed cache names, never paths.
        guard let fileName, fileName.count == 68, fileName.hasSuffix(".jpg"),
              fileName.dropLast(4).allSatisfy({ $0.isHexDigit }) else { return nil }
        return directory.appendingPathComponent("Artwork", isDirectory: true).appendingPathComponent(fileName)
    }

    func writeArtwork(_ data: Data, fileName: String) throws {
        guard let url = artworkURL(fileName: fileName) else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        // ponytail: retain 20 thumbnails; provider entries embed image data, not file references.
        let files = try FileManager.default.contentsOfDirectory(
            at: url.deletingLastPathComponent(), includingPropertiesForKeys: [.contentModificationDateKey]
        ).filter { artworkURL(fileName: $0.lastPathComponent) != nil }
        let sorted = files.sorted {
            let lhs = try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let rhs = try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return (lhs ?? .distantPast) > (rhs ?? .distantPast)
        }
        for old in sorted.dropFirst(20) where old != url { try? FileManager.default.removeItem(at: old) }
    }
}
