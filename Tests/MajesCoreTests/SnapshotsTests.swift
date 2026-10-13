import Foundation
import Testing
@testable import MajesCore

@Test func parsesTmutilListing() {
    let s = Snapshots.parse("Snapshots for disk /:\ncom.apple.TimeMachine.2026-10-13-101010.local\ncom.bombich.ccc.123\n")
    #expect(s.count == 2)
    #expect(s[0].timeMachineDate == "2026-10-13-101010" && s[0].isDeletable)
    #expect(!s[1].isDeletable && Snapshots.deleteCommand(s[1]) == nil)
    #expect(Snapshots.deleteCommand(s[0]) == ["/usr/bin/tmutil", "deletelocalsnapshots", "2026-10-13-101010"])
    #expect(Snapshots.parse("Snapshots for disk /:\n").isEmpty)
    #expect(Snapshots.purgeCommand(mountPath: "/") == ["/usr/bin/tmutil", "thinlocalsnapshots", "/", "999999999999999", "4"])
}

@Test func setVirtualSizeAdjustsAncestors() {
    let t = sampleTree()
    HiddenSpace.attach(HiddenSpaceBreakdown(purgeable: 50, otherVolumes: 10, stillHidden: 0), to: t)
    let h = t.children(t.root).first { t.virtualKind($0) == .hiddenSpace }!
    let p = t.children(h).first { t.virtualKind($0) == .purgeable }!
    t.setVirtualSize(p, 20)
    #expect(t.size(p) == 20 && t.size(h) == 30 && t.size(t.root) == 430)
}

@Test func liveSnapshotListingDoesNotCrash() {
    _ = Snapshots.list(mountPath: "/")
}
