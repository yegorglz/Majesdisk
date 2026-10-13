import Foundation
import Testing
@testable import MajesCore
@testable import MajesMap

@Test func hitCenterRingAndAngle() {
    let t = abcTree()
    let segs = SunburstLayout.layout(tree: t, center: t.root)
    let cfg = SunburstConfig()
    func hit(_ x: Double, _ y: Double) -> HitResult {
        SunburstHitTest.hit(point: CGPoint(x: x, y: y), center: CGPoint(x: 100, y: 100), outerRadius: 100, segments: segs, config: cfg)
    }
    let a = segs.firstIndex { $0.depth == 1 && $0.startAngle == 0 }!
    let bIdx = segs.firstIndex { $0.depth == 1 && t.name($0.node) == "B" }!
    #expect(hit(100, 100) == .center)
    #expect(hit(130, 99) == .segment(a))
    #expect(hit(100, 130) == .segment(bIdx))
    #expect(hit(100, -5) == .none)
    let r = cfg.radii(depth: 2, outerRadius: 100)
    #expect(hit(100 + (r.inner + r.outer) / 2, 99) == .segment(segs.firstIndex { $0.depth == 2 && $0.startAngle == 0 }!))
}
