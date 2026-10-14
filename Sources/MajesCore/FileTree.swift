import Foundation

/// Scan result as an index arena: parallel arrays indexed by `NodeID`. IDs never move;
/// only the per-folder `childIDs` lists are reordered. Mutate from one thread at a time.
public final class FileTree: @unchecked Sendable {
    public let rootPath: String
    var names: [String] = []
    var parents: [NodeID] = []
    var sizes: [UInt64] = []
    var itemCounts: [Int32] = []
    var flagList: [NodeFlags] = []
    var childIDs: [[NodeID]] = []
    var virtualKinds: [NodeID: VirtualKind] = [:]

    public var root: NodeID { 0 }
    public var nodeCount: Int { names.count }

    init(rootPath: String) {
        self.rootPath = rootPath
        _ = addNode(name: rootPath, parent: -1, size: 0, flags: .directory)
    }

    /// Rebuilds child lists from parent pointers (used by TreeCodec).
    init(rootPath: String, names: [String], parents: [NodeID], sizes: [UInt64], itemCounts: [Int32],
         flags: [NodeFlags], virtualKinds: [NodeID: VirtualKind]) {
        self.rootPath = rootPath
        self.names = names; self.parents = parents; self.sizes = sizes; self.itemCounts = itemCounts
        self.flagList = flags; self.virtualKinds = virtualKinds
        childIDs = Array(repeating: [], count: names.count)
        for id in 1..<max(1, names.count) where parents[id] >= 0 { childIDs[Int(parents[id])].append(NodeID(id)) }
        sortAllChildren()
    }

    func addNode(name: String, parent: NodeID, size: UInt64, flags: NodeFlags) -> NodeID {
        let id = NodeID(names.count)
        names.append(name); parents.append(parent); sizes.append(size)
        itemCounts.append(0); flagList.append(flags); childIDs.append([])
        if parent >= 0 { childIDs[Int(parent)].append(id) }
        return id
    }

    // MARK: Queries

    public func name(_ id: NodeID) -> String { names[Int(id)] }
    public func size(_ id: NodeID) -> UInt64 { sizes[Int(id)] }
    /// Number of files and folders beneath this node (0 for files).
    public func itemCount(_ id: NodeID) -> Int { Int(itemCounts[Int(id)]) }
    public func flags(_ id: NodeID) -> NodeFlags { flagList[Int(id)] }
    public func parent(_ id: NodeID) -> NodeID? { let p = parents[Int(id)]; return p < 0 ? nil : p }
    public func virtualKind(_ id: NodeID) -> VirtualKind? { virtualKinds[id] }

    public func children(_ id: NodeID) -> [NodeID] {
        childIDs[Int(id)].filter { !flagList[Int($0)].contains(.deleted) }
    }

    public func path(_ id: NodeID) -> String {
        var parts: [String] = []
        var cur = id
        while let p = parent(cur) { parts.append(names[Int(cur)]); cur = p }
        if parts.isEmpty { return rootPath }
        let tail = parts.reversed().joined(separator: "/")
        return rootPath.hasSuffix("/") ? rootPath + tail : rootPath + "/" + tail
    }

    public func node(atPath path: String) -> NodeID? {
        if path == rootPath { return root }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard path.hasPrefix(prefix) else { return nil }
        var cur = root
        for comp in path.dropFirst(prefix.count).split(separator: "/") {
            guard let next = children(cur).first(where: { names[Int($0)] == comp }) else { return nil }
            cur = next
        }
        return cur
    }

    /// Deleted itself or inside a deleted folder (only the deleted folder carries the flag).
    public func isGone(_ id: NodeID) -> Bool {
        var cur: NodeID? = id
        while let c = cur { if flagList[Int(c)].contains(.deleted) { return true }; cur = parent(c) }
        return false
    }

    public func isAncestor(_ a: NodeID, of b: NodeID) -> Bool {
        var cur = parent(b)
        while let c = cur { if c == a { return true }; cur = parent(c) }
        return false
    }

    // MARK: Mutation (main thread)

    public func markDeleted(_ id: NodeID) {
        guard id != root, !flagList[Int(id)].contains(.deleted) else { return }
        flagList[Int(id)].insert(.deleted)
        adjustAncestors(of: id, sizeDelta: -Int64(sizes[Int(id)]), itemDelta: -(itemCounts[Int(id)] + 1))
    }

    @discardableResult
    public func appendVirtual(parent: NodeID, name: String, size: UInt64, kind: VirtualKind) -> NodeID {
        let id = addNode(name: name, parent: parent, size: size, flags: .virtual)
        virtualKinds[id] = kind
        adjustAncestors(of: id, sizeDelta: Int64(size), itemDelta: 0)
        return id
    }

    /// Changes a virtual node's size (e.g. purgeable space after a purge) and its ancestors'.
    public func setVirtualSize(_ id: NodeID, _ size: UInt64) {
        let delta = Int64(size) - Int64(sizes[Int(id)])
        sizes[Int(id)] = size
        adjustAncestors(of: id, sizeDelta: delta, itemDelta: 0)
    }

    /// Grafts a fresh scan of this folder in place of its old contents.
    public func replaceSubtree(of id: NodeID, with fresh: FileTree) {
        for c in childIDs[Int(id)] { flagList[Int(c)].insert(.deleted) }
        childIDs[Int(id)] = []
        var map: [NodeID: NodeID] = [fresh.root: id]
        for f in 1..<max(1, fresh.nodeCount) {
            let fid = NodeID(f)
            let newID = addNode(name: fresh.names[f], parent: map[fresh.parents[f]]!, size: fresh.sizes[f], flags: fresh.flagList[f])
            itemCounts[Int(newID)] = fresh.itemCounts[f]
            if let k = fresh.virtualKinds[fid] { virtualKinds[newID] = k }
            map[fid] = newID
            sortChildren(newID)
        }
        sortChildren(id)
        let sizeDelta = Int64(fresh.size(fresh.root)) - Int64(sizes[Int(id)])
        let itemDelta = fresh.itemCounts[0] - itemCounts[Int(id)]
        sizes[Int(id)] = fresh.size(fresh.root); itemCounts[Int(id)] = fresh.itemCounts[0]
        flagList[Int(id)].remove(.restricted)
        if fresh.flagList[0].contains(.restricted) { flagList[Int(id)].insert(.restricted) }
        adjustAncestors(of: id, sizeDelta: sizeDelta, itemDelta: itemDelta)
    }

    func adjustAncestors(of id: NodeID, sizeDelta: Int64, itemDelta: Int32) {
        var cur = parent(id)
        while let p = cur {
            sizes[Int(p)] = UInt64(max(0, Int64(sizes[Int(p)]) + sizeDelta))
            itemCounts[Int(p)] += itemDelta
            sortChildren(p)
            cur = parent(p)
        }
    }

    // MARK: Ordering — size descending, then name

    func sortChildren(_ id: NodeID) {
        childIDs[Int(id)].sort { a, b in
            let sa = sizes[Int(a)], sb = sizes[Int(b)]
            if sa != sb { return sa > sb }
            return names[Int(a)].localizedStandardCompare(names[Int(b)]) == .orderedAscending
        }
    }

    func sortAllChildren() {
        for i in 0..<childIDs.count where childIDs[i].count > 1 { sortChildren(NodeID(i)) }
    }
}
