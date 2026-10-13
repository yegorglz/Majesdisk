/// Accumulates directory listings into a `FileTree`. Not thread-safe: callers serialize access.
public final class FileTreeBuilder {
    let tree: FileTree
    private var seenSharedData = Set<UInt64>()

    public init(rootPath: String) { tree = FileTree(rootPath: rootPath) }
    public var root: NodeID { tree.root }

    public func markRestricted(_ id: NodeID) { tree.flagList[Int(id)].insert(.restricted) }

    @discardableResult
    public func appendChildren(of parent: NodeID, entries: [DirEntry]) -> [NodeID] {
        entries.map { e in
            var flags: NodeFlags = []
            var size = e.allocatedSize
            switch e.kind {
            case .directory:
                flags.insert(.directory)
                if PackageExtensions.isPackage(name: e.name) { flags.insert(.package) }
            case .symlink: flags.insert(.symlink)
            default: break
            }
            if e.isMountPoint { flags.insert(.mountPoint) }
            if e.isDataless { flags.insert(.dataless) }
            // Hard links share a file ID and full clones share a clone ID: count the data once.
            if e.kind != .directory, e.linkCount > 1 || e.cloneRefCount > 1 {
                let key = e.cloneID != 0 ? e.cloneID : e.fileID
                if !seenSharedData.insert(key).inserted { size = 0; flags.insert(.secondaryLink) }
            }
            return tree.addNode(name: e.name, parent: parent, size: size, flags: flags)
        }
    }

    public func finish() -> FileTree {
        // Children always have larger IDs than their parent, so one reverse pass aggregates bottom-up.
        for i in stride(from: tree.nodeCount - 1, to: 0, by: -1) {
            let p = Int(tree.parents[i])
            tree.sizes[p] += tree.sizes[i]
            tree.itemCounts[p] += tree.itemCounts[i] + 1
        }
        tree.sortAllChildren()
        return tree
    }
}
