import Foundation

public enum TreeCodecError: Error, Equatable { case badMagic, truncated }

/// Compact binary form of a FileTree, used to hand an admin scan from the root helper to the app.
/// Little-endian: "MJD1", u32 count, per node (i32 parent, u16 flags, u64 size, u32 items, u16 len, utf8),
/// then u32 virtual count and (i32 id, u8 kind) pairs, then u32 link count and (i32 id, u64 key) pairs.
/// Node 0's name is the root path.
public enum TreeCodec {
    static let magic = Data("MJD1".utf8)

    public static func encode(_ t: FileTree) -> Data {
        var d = magic
        func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        put(UInt32(t.nodeCount))
        for i in 0..<t.nodeCount {
            put(t.parents[i]); put(t.flagList[i].rawValue); put(t.sizes[i]); put(UInt32(max(0, t.itemCounts[i])))
            let name = Data(t.names[i].utf8.prefix(Int(UInt16.max)))
            put(UInt16(name.count)); d.append(name)
        }
        put(UInt32(t.virtualKinds.count))
        for (id, kind) in t.virtualKinds.sorted(by: { $0.key < $1.key }) { put(id); put(kind.rawValue) }
        put(UInt32(t.linkKeys.count))
        for (id, key) in t.linkKeys.sorted(by: { $0.key < $1.key }) { put(id); put(key) }
        return d
    }

    public static func decode(_ data: Data) throws -> FileTree {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, Data(bytes[0..<4]) == magic else { throw TreeCodecError.badMagic }
        var pos = 4
        func get<T: FixedWidthInteger>(_: T.Type) throws -> T {
            let n = MemoryLayout<T>.size
            guard pos + n <= bytes.count else { throw TreeCodecError.truncated }
            var v: T = 0
            for k in 0..<n { v |= T(truncatingIfNeeded: bytes[pos + k]) << (8 * k) }
            pos += n
            return v
        }
        let count = Int(try get(UInt32.self))
        guard count > 0, count <= bytes.count else { throw TreeCodecError.truncated }
        var names: [String] = [], parents: [NodeID] = [], sizes: [UInt64] = [], items: [Int32] = [], flags: [NodeFlags] = []
        names.reserveCapacity(count); parents.reserveCapacity(count); sizes.reserveCapacity(count)
        for i in 0..<count {
            let parent = try get(Int32.self)
            guard parent < Int32(i), i == 0 || parent >= 0 else { throw TreeCodecError.truncated }
            parents.append(parent)
            flags.append(NodeFlags(rawValue: try get(UInt16.self)))
            sizes.append(try get(UInt64.self))
            items.append(Int32(clamping: try get(UInt32.self)))
            let len = Int(try get(UInt16.self))
            guard pos + len <= bytes.count else { throw TreeCodecError.truncated }
            names.append(String(decoding: bytes[pos..<pos + len], as: UTF8.self))
            pos += len
        }
        var virtuals: [NodeID: VirtualKind] = [:]
        for _ in 0..<Int(try get(UInt32.self)) {
            let id = try get(Int32.self)
            if let k = VirtualKind(rawValue: try get(UInt8.self)), id >= 0, Int(id) < count { virtuals[id] = k }
        }
        var links: [NodeID: UInt64] = [:]
        for _ in 0..<Int(try get(UInt32.self)) {
            let id = try get(Int32.self), key = try get(UInt64.self)
            if id >= 0, Int(id) < count { links[id] = key }
        }
        return FileTree(rootPath: names[0], names: names, parents: parents, sizes: sizes, itemCounts: items,
                        flags: flags, virtualKinds: virtuals, linkKeys: links)
    }
}
