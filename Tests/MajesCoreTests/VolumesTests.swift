import Foundation
import Testing
@testable import MajesCore

@Test func otherVolumesExcludesSystemAndDataForRootScan() throws {
    let plist = try PropertyListSerialization.data(fromPropertyList: ["Containers": [["ContainerReference": "disk3", "Volumes": [
        ["Name": "Macintosh HD", "DeviceIdentifier": "disk3s1", "Roles": ["System"], "CapacityInUse": 12],
        ["Name": "Data", "DeviceIdentifier": "disk3s5", "Roles": ["Data"], "CapacityInUse": 90],
        ["Name": "Preboot", "DeviceIdentifier": "disk3s2", "Roles": ["Preboot"], "CapacityInUse": 7],
        ["Name": "VM", "DeviceIdentifier": "disk3s6", "Roles": ["VM"], "CapacityInUse": 3]]]]], format: .xml, options: 0)
    let cs = try APFSInfo.parseContainers(plist)
    let disk = DiskInfoRecord(deviceIdentifier: "disk3s1s1", containerReference: "disk3", isSolidState: true)
    #expect(APFSInfo.otherVolumesBytes(containers: cs, scanned: disk, isRootScan: true) == 10)
    let ext = DiskInfoRecord(deviceIdentifier: "disk3s2", containerReference: "disk3", isSolidState: true)
    #expect(APFSInfo.otherVolumesBytes(containers: cs, scanned: ext, isRootScan: false) == 12 + 90 + 3)
    let none = DiskInfoRecord(deviceIdentifier: "disk9s1", containerReference: nil, isSolidState: nil)
    #expect(APFSInfo.otherVolumesBytes(containers: cs, scanned: none, isRootScan: false) == 0)
}

@Test func parsesDiskInfo() throws {
    let plist = try PropertyListSerialization.data(fromPropertyList: ["DeviceIdentifier": "disk3s1s1", "APFSContainerReference": "disk3", "SolidState": true], format: .xml, options: 0)
    #expect(try APFSInfo.parseDiskInfo(plist) == DiskInfoRecord(deviceIdentifier: "disk3s1s1", containerReference: "disk3", isSolidState: true))
}

@Test func gaugeThresholds() {
    #expect(GaugeLevel.forFraction(0.5) == .green)
    #expect(GaugeLevel.forFraction(0.85) == .orange)
    #expect(GaugeLevel.forFraction(0.86) == .red)
}

@Test func volumeMath() {
    let v = VolumeInfo(name: "X", mountPath: "/x", fileSystem: "APFS", totalBytes: 100, availableBytes: 40,
                       availableImportantBytes: 50, isRootFileSystem: false, isInternal: true, isRemovable: false, isLocal: true)
    #expect(v.usedBytes == 60 && v.purgeableBytes == 10)
    #expect(v.usedFraction(purgeableAsUsed: true) == 0.6)
    #expect(v.usedFraction(purgeableAsUsed: false) == 0.5)
}

@Test func liveVolumesIncludeRootFirst() {
    let v = VolumeLister.mountedVolumes()
    #expect(v.first?.mountPath == "/")
    #expect(v.first!.totalBytes > 0)
    #expect(APFSInfo.diskInfo(mountPath: "/")?.containerReference != nil)
    #expect(!APFSInfo.containers().isEmpty)
}
