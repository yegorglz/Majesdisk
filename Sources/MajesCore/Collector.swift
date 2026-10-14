public enum CollectorAddResult: Equatable, Sendable { case added, alreadyCovered, rejected(String) }

/// Items queued for deletion. Holding a folder covers everything inside it.
public struct Collector: Sendable {
    public private(set) var items: [NodeID] = []
    public init() {}

    public mutating func add(_ id: NodeID, in tree: FileTree, verdict: (String) -> ProtectionVerdict) -> CollectorAddResult {
        if id == tree.root { return .rejected("The scanned folder itself can't be collected.") }
        if let kind = tree.virtualKind(id), kind != .purgeable { return .rejected("This is a summary of space, not a file.") }
        if items.contains(where: { $0 == id || tree.isAncestor($0, of: id) }) { return .alreadyCovered }
        if tree.virtualKind(id) == nil, case .protected(let why) = verdict(tree.path(id)) { return .rejected(why) }
        items.removeAll { tree.isAncestor(id, of: $0) }
        items.append(id)
        return .added
    }

    public mutating func remove(_ id: NodeID) { items.removeAll { $0 == id } }
    public mutating func removeAll() { items.removeAll() }
    /// After `FileTree.compact()`.
    public mutating func remap(_ map: [NodeID: NodeID]) { items = items.compactMap { map[$0] } }
    public func contains(_ id: NodeID) -> Bool { items.contains(id) }
    public func totalSize(in tree: FileTree) -> UInt64 { items.reduce(0) { $0 + tree.size($1) } }
}
