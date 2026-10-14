public typealias NodeID = Int32

/// One item returned by a directory read.
public struct DirEntry: Sendable, Equatable {
    public enum Kind: UInt8, Sendable { case file, directory, symlink, other }
    public var name: String
    public var kind: Kind
    public var allocatedSize: UInt64
    public var fileID: UInt64
    public var linkCount: UInt32
    public var cloneID: UInt64
    public var cloneRefCount: UInt32
    public var isMountPoint: Bool
    public var isDataless: Bool

    public init(name: String, kind: Kind, allocatedSize: UInt64 = 0, fileID: UInt64 = 0, linkCount: UInt32 = 1,
                cloneID: UInt64 = 0, cloneRefCount: UInt32 = 1, isMountPoint: Bool = false,
                isDataless: Bool = false) {
        self.name = name; self.kind = kind; self.allocatedSize = allocatedSize; self.fileID = fileID
        self.linkCount = linkCount; self.cloneID = cloneID; self.cloneRefCount = cloneRefCount
        self.isMountPoint = isMountPoint; self.isDataless = isDataless
    }
}

public struct NodeFlags: OptionSet, Sendable, Hashable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public static let directory = NodeFlags(rawValue: 1 << 0)
    public static let package = NodeFlags(rawValue: 1 << 1)
    public static let symlink = NodeFlags(rawValue: 1 << 2)
    public static let restricted = NodeFlags(rawValue: 1 << 3)
    public static let secondaryLink = NodeFlags(rawValue: 1 << 4)
    public static let deleted = NodeFlags(rawValue: 1 << 5)
    public static let virtual = NodeFlags(rawValue: 1 << 6)
    public static let mountPoint = NodeFlags(rawValue: 1 << 7)
    public static let dataless = NodeFlags(rawValue: 1 << 8)
}

public enum VirtualKind: UInt8, Sendable { case hiddenSpace, purgeable, otherVolumes, stillHidden }
