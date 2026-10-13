import Foundation

public struct VolumeInfo: Identifiable, Sendable, Equatable {
    public var id: String { mountPath }
    public var name: String
    public var mountPath: String
    public var fileSystem: String
    public var totalBytes: UInt64
    public var availableBytes: UInt64
    public var availableImportantBytes: UInt64
    public var isRootFileSystem: Bool
    public var isInternal: Bool
    public var isRemovable: Bool
    public var isLocal: Bool

    public init(name: String, mountPath: String, fileSystem: String, totalBytes: UInt64, availableBytes: UInt64,
                availableImportantBytes: UInt64, isRootFileSystem: Bool, isInternal: Bool, isRemovable: Bool, isLocal: Bool) {
        self.name = name; self.mountPath = mountPath; self.fileSystem = fileSystem; self.totalBytes = totalBytes
        self.availableBytes = availableBytes; self.availableImportantBytes = availableImportantBytes
        self.isRootFileSystem = isRootFileSystem; self.isInternal = isInternal; self.isRemovable = isRemovable; self.isLocal = isLocal
    }

    /// Includes purgeable space (macOS counts it as used until it's reclaimed).
    public var usedBytes: UInt64 { totalBytes > availableBytes ? totalBytes - availableBytes : 0 }
    public var purgeableBytes: UInt64 { availableImportantBytes > availableBytes ? availableImportantBytes - availableBytes : 0 }
    /// Free space as Finder shows it: purgeable counts as free.
    public var freeBytes: UInt64 { max(availableBytes, availableImportantBytes) }

    public func usedFraction(purgeableAsUsed: Bool) -> Double {
        guard totalBytes > 0 else { return 0 }
        let used = purgeableAsUsed ? usedBytes : usedBytes - min(usedBytes, purgeableBytes)
        return Double(used) / Double(totalBytes)
    }
}

public enum GaugeLevel: Sendable {
    case green, orange, red
    public static func forFraction(_ f: Double) -> GaugeLevel { f <= 0.5 ? .green : f <= 0.85 ? .orange : .red }
}

public enum VolumeLister {
    static let keys: [URLResourceKey] = [
        .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        .volumeIsRootFileSystemKey, .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsLocalKey,
        .volumeLocalizedFormatDescriptionKey,
    ]

    public static func mountedVolumes() -> [VolumeInfo] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return sorted(urls.compactMap(info(for:)))
    }

    public static func info(for url: URL) -> VolumeInfo? {
        guard let v = try? url.resourceValues(forKeys: Set(keys)), let total = v.volumeTotalCapacity, total > 0 else { return nil }
        let avail = UInt64(max(0, v.volumeAvailableCapacity ?? 0))
        return VolumeInfo(name: v.volumeName ?? url.lastPathComponent, mountPath: url.path, fileSystem: v.volumeLocalizedFormatDescription ?? "",
                          totalBytes: UInt64(total), availableBytes: avail,
                          availableImportantBytes: UInt64(max(0, v.volumeAvailableCapacityForImportantUsage ?? Int64(avail))),
                          isRootFileSystem: v.volumeIsRootFileSystem ?? false, isInternal: v.volumeIsInternal ?? false,
                          isRemovable: v.volumeIsRemovable ?? false, isLocal: v.volumeIsLocal ?? true)
    }

    public static func sorted(_ v: [VolumeInfo]) -> [VolumeInfo] {
        v.sorted { a, b in
            if a.isRootFileSystem != b.isRootFileSystem { return a.isRootFileSystem }
            if a.isInternal != b.isInternal { return a.isInternal }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
