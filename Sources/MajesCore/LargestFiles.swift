/// What a big item is, by extension; drives the "Largest" filters.
public enum FileKind: String, CaseIterable, Sendable {
    case video, archives, apps, other

    static let videoExts: Set<String> = ["mov", "mp4", "m4v", "mkv", "avi", "wmv", "mpg", "mpeg", "webm", "mts", "m2ts", "3gp", "braw", "r3d"]
    static let archiveExts: Set<String> = ["dmg", "iso", "zip", "pkg", "mpkg", "xip", "tar", "gz", "tgz", "bz2", "xz", "rar", "7z", "img", "sparseimage", "sparsebundle", "ipsw"]

    public static func of(name: String, flags: NodeFlags) -> FileKind {
        let ext = name.split(separator: ".").last.map { $0.lowercased() } ?? ""
        if flags.contains(.package) && ext == "app" { return .apps }
        if videoExts.contains(ext) { return .video }
        if archiveExts.contains(ext) { return .archives }
        return .other
    }
}

extension FileTree {
    /// The biggest files under `root`, anywhere deep — packages (apps, libraries) count as single items.
    /// Keeps a bounded, sorted top list, so it's one pass over the subtree.
    public func largestFiles(under root: NodeID, limit: Int, kind: FileKind? = nil) -> [NodeID] {
        var top: [NodeID] = []
        var stack = [root]
        while let n = stack.popLast() {
            for c in children(n) {
                let f = flags(c)
                if f.contains(.virtual) { continue }
                if f.contains(.directory) && !f.contains(.package) { stack.append(c); continue }
                let size = self.size(c)
                guard size > 0, top.count < limit || size > self.size(top[top.count - 1]) else { continue }
                if let kind, FileKind.of(name: name(c), flags: f) != kind { continue }
                // Binary search for the insertion point in the descending list.
                var lo = 0, hi = top.count
                while lo < hi { let mid = (lo + hi) / 2; if self.size(top[mid]) >= size { lo = mid + 1 } else { hi = mid } }
                top.insert(c, at: lo)
                if top.count > limit { top.removeLast() }
            }
        }
        return top
    }
}
