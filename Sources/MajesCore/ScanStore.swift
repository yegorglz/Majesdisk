import CryptoKit
import Foundation

/// Finished scans on disk (Application Support/MajesDisk/Scans), so results survive a relaunch and
/// a later scan can be compared with the previous one. One file per scanned root.
public struct ScanStore: Sendable {
    public let directory: URL
    private var index: URL { directory.appendingPathComponent("index.plist") }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MajesDisk/Scans", isDirectory: true)
    }

    public init(directory: URL = ScanStore.defaultDirectory) { self.directory = directory }

    /// Root path → when it was scanned.
    public func saved() -> [String: Date] {
        guard let data = try? Data(contentsOf: index) else { return [:] }
        return (try? PropertyListDecoder().decode([String: Date].self, from: data)) ?? [:]
    }

    public func save(_ tree: FileTree, scannedAt: Date = Date()) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try TreeCodec.encode(tree).write(to: file(for: tree.rootPath), options: .atomic)
        var all = saved()
        all[tree.rootPath] = scannedAt
        try PropertyListEncoder().encode(all).write(to: index, options: .atomic)
    }

    public func load(_ rootPath: String) throws -> FileTree? {
        guard saved()[rootPath] != nil, let data = try? Data(contentsOf: file(for: rootPath)) else { return nil }
        return try TreeCodec.decode(data)
    }

    public func remove(_ rootPath: String) {
        try? FileManager.default.removeItem(at: file(for: rootPath))
        var all = saved()
        all[rootPath] = nil
        try? PropertyListEncoder().encode(all).write(to: index, options: .atomic)
    }

    /// Paths can be longer than a file name allows, so files are named by a hash of the path.
    private func file(for rootPath: String) -> URL {
        let hash = SHA256.hash(data: Data(rootPath.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".mjd")
    }
}
