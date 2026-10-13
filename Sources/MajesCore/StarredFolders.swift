import Foundation

/// Folders pinned to the disks overview, kept across launches.
public struct StarredFolders {
    static let key = "starredFolders"
    let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var paths: [String] { defaults.stringArray(forKey: Self.key) ?? [] }
    public func contains(_ p: String) -> Bool { paths.contains(p) }
    public func add(_ p: String) { if !contains(p) { defaults.set(paths + [p], forKey: Self.key) } }
    public func remove(_ p: String) { defaults.set(paths.filter { $0 != p }, forKey: Self.key) }
}
