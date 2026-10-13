import Foundation

public struct APFSVolumeRecord: Sendable, Equatable {
    public var name: String; public var deviceIdentifier: String; public var roles: [String]; public var capacityInUse: UInt64
}
public struct APFSContainerRecord: Sendable, Equatable { public var reference: String; public var volumes: [APFSVolumeRecord] }
public struct DiskInfoRecord: Sendable, Equatable {
    public var deviceIdentifier: String; public var containerReference: String?; public var isSolidState: Bool?
    public init(deviceIdentifier: String, containerReference: String?, isSolidState: Bool?) {
        self.deviceIdentifier = deviceIdentifier; self.containerReference = containerReference; self.isSolidState = isSolidState
    }
}

/// Reads `diskutil` plists to find space used by sibling APFS volumes.
public enum APFSInfo {
    struct BadPlist: Error {}

    public static func parseContainers(_ plist: Data) throws -> [APFSContainerRecord] {
        guard let root = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
              let cs = root["Containers"] as? [[String: Any]] else { throw BadPlist() }
        return cs.map { c in
            APFSContainerRecord(reference: c["ContainerReference"] as? String ?? "",
                                volumes: (c["Volumes"] as? [[String: Any]] ?? []).map { v in
                APFSVolumeRecord(name: v["Name"] as? String ?? "", deviceIdentifier: v["DeviceIdentifier"] as? String ?? "",
                                 roles: v["Roles"] as? [String] ?? [], capacityInUse: (v["CapacityInUse"] as? NSNumber)?.uint64Value ?? 0)
            })
        }
    }

    public static func parseDiskInfo(_ plist: Data) throws -> DiskInfoRecord {
        guard let d = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
              let dev = d["DeviceIdentifier"] as? String else { throw BadPlist() }
        return DiskInfoRecord(deviceIdentifier: dev, containerReference: d["APFSContainerReference"] as? String,
                              isSolidState: d["SolidState"] as? Bool)
    }

    public static func otherVolumesBytes(containers: [APFSContainerRecord], scanned: DiskInfoRecord, isRootScan: Bool) -> UInt64 {
        guard let ref = scanned.containerReference, let c = containers.first(where: { $0.reference == ref }) else { return 0 }
        // disk3s1s1 is the sealed snapshot of volume disk3s1.
        let base = scanned.deviceIdentifier.firstMatch(of: #/^disk\d+s\d+/#).map { String($0.output) } ?? scanned.deviceIdentifier
        return c.volumes.filter { v in
            v.deviceIdentifier != base && !(isRootScan && (v.roles.contains("System") || v.roles.contains("Data")))
        }.reduce(0) { $0 + $1.capacityInUse }
    }

    public static func diskInfo(mountPath: String) -> DiskInfoRecord? {
        run(["info", "-plist", mountPath]).flatMap { try? parseDiskInfo($0) }
    }

    public static func containers() -> [APFSContainerRecord] {
        run(["apfs", "list", "-plist"]).flatMap { try? parseContainers($0) } ?? []
    }

    static func run(_ args: [String]) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? data : nil
    }
}
