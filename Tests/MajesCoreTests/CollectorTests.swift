import Foundation
import Testing
@testable import MajesCore

private let allow: (String) -> ProtectionVerdict = { _ in .allowed }

@Test func collectorCoversDescendantsAndRejects() {
    let t = sampleTree()
    var c = Collector()
    let a = t.node(atPath: "/r/a")!, g = t.node(atPath: "/r/a/g")!, f = t.node(atPath: "/r/f")!
    #expect(c.add(a, in: t, verdict: allow) == .added)
    #expect(c.add(g, in: t, verdict: allow) == .alreadyCovered)
    #expect(c.add(a, in: t, verdict: allow) == .alreadyCovered)
    if case .rejected = c.add(t.root, in: t, verdict: allow) {} else { Issue.record("root must be rejected") }
    #expect(c.add(f, in: t, verdict: allow) == .added)
    #expect(c.totalSize(in: t) == 400)
    c.remove(a)
    #expect(c.items == [f])

    var d = Collector()
    #expect(d.add(g, in: t, verdict: allow) == .added)
    #expect(d.add(a, in: t, verdict: allow) == .added)
    #expect(d.items == [a])

    var e = Collector()
    if case .rejected("nope") = e.add(f, in: t, verdict: { _ in .protected("nope") }) {} else { Issue.record("protected must be rejected") }
}

@Test func collectorVirtualRules() {
    let t = sampleTree()
    HiddenSpace.attach(HiddenSpaceBreakdown(purgeable: 5, otherVolumes: 5, stillHidden: 5), to: t)
    let h = t.children(t.root).first { t.virtualKind($0) == .hiddenSpace }!
    var c = Collector()
    if case .rejected = c.add(h, in: t, verdict: allow) {} else { Issue.record("hidden space must be rejected") }
    for k in t.children(h) where t.virtualKind(k) != .purgeable {
        if case .rejected = c.add(k, in: t, verdict: allow) {} else { Issue.record("\(t.name(k)) must be rejected") }
    }
    #expect(c.add(t.children(h).first { t.virtualKind($0) == .purgeable }!, in: t, verdict: allow) == .added)
}
