import Foundation
import Testing
@testable import MajesCore

@Test func hiddenSpaceSplitsRemainder() {
    let b = HiddenSpace.compute(usedBytes: 100, scannedBytes: 60, purgeableBytes: 25, otherVolumesBytes: 10)!
    #expect(b == HiddenSpaceBreakdown(purgeable: 25, otherVolumes: 10, stillHidden: 5))
    #expect(HiddenSpace.compute(usedBytes: 100, scannedBytes: 100, purgeableBytes: 5, otherVolumesBytes: 5) == nil)
    #expect(HiddenSpace.compute(usedBytes: 100, scannedBytes: 120, purgeableBytes: 5, otherVolumesBytes: 5) == nil)
    let c = HiddenSpace.compute(usedBytes: 100, scannedBytes: 90, purgeableBytes: 25, otherVolumesBytes: 10)!
    #expect(c == HiddenSpaceBreakdown(purgeable: 10, otherVolumes: 0, stillHidden: 0))
}

@Test func attachBuildsVirtualSubtree() {
    let t = sampleTree()
    HiddenSpace.attach(HiddenSpaceBreakdown(purgeable: 25, otherVolumes: 10, stillHidden: 5), to: t)
    #expect(t.size(t.root) == 440)
    let h = t.children(t.root).first { t.virtualKind($0) == .hiddenSpace }!
    #expect(t.children(h).compactMap(t.virtualKind) == [.purgeable, .otherVolumes, .stillHidden])
    let t2 = sampleTree()
    HiddenSpace.attach(HiddenSpaceBreakdown(purgeable: 0, otherVolumes: 10, stillHidden: 0), to: t2)
    let h2 = t2.children(t2.root).first { t2.virtualKind($0) == .hiddenSpace }!
    #expect(t2.children(h2).compactMap(t2.virtualKind) == [.otherVolumes])
}
