/// A big folder that's known to be safe (or nearly) to remove, with a one-line explanation.
public struct CleanupSuggestion: Equatable, Sendable {
    public var node: NodeID
    public var title: String
    public var note: String
}

/// Finds well-known, regenerable space hogs in every home folder of a scan.
public enum CleanupSuggestions {
    static let homeRules: [(path: String, title: String, note: String)] = [
        ("Library/Developer/Xcode/DerivedData", "Xcode build data", "Xcode rebuilds it on the next build. Safe to delete."),
        ("Library/Developer/Xcode/Archives", "Xcode archives", "Builds you archived for release. Keep any you may need to re-submit or debug."),
        ("Library/Developer/Xcode/iOS DeviceSupport", "iOS device support", "Downloaded again when a device connects. Safe to delete for iOS versions you no longer test."),
        ("Library/Developer/CoreSimulator/Caches", "Simulator caches", "Rebuilt when needed. Safe to delete."),
        ("Library/Developer/CoreSimulator/Devices", "iOS simulators", "Every simulator with its apps and data. `xcrun simctl delete unavailable` removes only the outdated ones."),
        ("Library/Caches", "App caches", "Apps rebuild their caches. Safe to delete; some apps start slower once."),
        ("Library/Application Support/MobileSync/Backup", "iPhone and iPad backups", "Local device backups. Delete only the ones you no longer need."),
        ("Library/Containers/com.docker.docker/Data/vms", "Docker disk image", "All Docker images and containers. `docker system prune` frees space more gently."),
        (".Trash", "Trash", "Files you already deleted. Emptying it is permanent."),
        (".npm", "npm cache", "Packages npm downloads again when needed. Safe to delete."),
        (".gradle/caches", "Gradle caches", "Rebuilt by the next build. Safe to delete."),
        (".cocoapods/repos", "CocoaPods specs", "Downloaded again by `pod install`. Safe to delete."),
    ]

    /// Homes are the children of any "Users" folder near the top of the scan, plus `extraHomes`.
    public static func find(in tree: FileTree, extraHomes: [String] = [], minSize: UInt64 = 50_000_000) -> [CleanupSuggestion] {
        var homes = Set(extraHomes)
        var level = [tree.root]
        for _ in 0..<3 {
            level = level.flatMap(tree.children)
            for n in level where tree.name(n) == "Users" { tree.children(n).forEach { homes.insert(tree.path($0)) } }
        }
        var out: [CleanupSuggestion] = []
        for home in homes.sorted() {
            for rule in homeRules {
                if let n = tree.node(atPath: home + "/" + rule.path), tree.size(n) >= minSize {
                    out.append(CleanupSuggestion(node: n, title: rule.title, note: rule.note))
                }
            }
        }
        // Project dependency folders: the outermost node_modules of each project.
        var stack = [tree.root]
        var modules: [NodeID] = []
        while let n = stack.popLast() {
            for c in tree.children(n) where tree.flags(c).contains(.directory) {
                if tree.name(c) == "node_modules" { if tree.size(c) >= minSize { modules.append(c) } } else { stack.append(c) }
            }
        }
        for n in tree.sortedByOrder(modules).prefix(10) {
            let project = tree.parent(n).map(tree.name) ?? ""
            out.append(CleanupSuggestion(node: n, title: "node_modules in \(project)", note: "Installed again by `npm install` or `yarn`. Safe to delete for projects you aren't working on."))
        }
        return out.sorted { tree.size($0.node) > tree.size($1.node) }
    }
}
