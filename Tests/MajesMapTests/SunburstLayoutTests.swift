import Foundation
import Testing
@testable import MajesCore
@testable import MajesMap

/// root 100 = dir A (file 50), dir B (file 30), file C (20)
func abcTree() -> FileTree {
    let b = FileTreeBuilder(rootPath: "/r")
    let top = b.appendChildren(of: b.root, entries: [
        DirEntry(name: "A", kind: .directory), DirEntry(name: "B", kind: .directory),
        DirEntry(name: "C", kind: .file, allocatedSize: 20)])
    b.appendChildren(of: top[0], entries: [DirEntry(name: "a1", kind: .file, allocatedSize: 50)])
    b.appendChildren(of: top[1], entries: [DirEntry(name: "b1", kind: .file, allocatedSize: 30)])
    return b.finish()
}

@Test func anglesProportionalAndNested() {
    let t = abcTree()
    let segs = SunburstLayout.layout(tree: t, center: t.root)
    let d1 = segs.filter { $0.depth == 1 }
    #expect(d1.map { (($0.endAngle - $0.startAngle) / (2 * .pi) * 100).rounded() } == [50, 30, 20])
    #expect(segs.contains { $0.depth == 2 && abs($0.endAngle - .pi) < 1e-9 && $0.startAngle == 0 })
    #expect(d1[2].kind == .file && d1[0].kind == .directory)
}

@Test func tinyChildrenMergeIntoSmallerObjects() {
    let b = FileTreeBuilder(rootPath: "/r")
    b.appendChildren(of: b.root, entries: [DirEntry(name: "big", kind: .file, allocatedSize: 10_000)]
        + (0..<300).map { DirEntry(name: "t\($0)", kind: .file, allocatedSize: 1) })
    let t = b.finish()
    let d1 = SunburstLayout.layout(tree: t, center: t.root).filter { $0.depth == 1 }
    #expect(d1.count == 2)
    #expect(d1.last?.kind == .smallerObjects && d1.last?.aggregateStartIndex == 1 && d1.last?.node == t.root)
    #expect(abs(d1.last!.endAngle - 2 * .pi) < 1e-9)
}

@Test func depthIsCapped() {
    let b = FileTreeBuilder(rootPath: "/r")
    var cur = b.root
    for i in 0..<10 { cur = b.appendChildren(of: cur, entries: [DirEntry(name: "d\(i)", kind: .directory)])[0] }
    b.appendChildren(of: cur, entries: [DirEntry(name: "f", kind: .file, allocatedSize: 1)])
    let t = b.finish()
    #expect(SunburstLayout.layout(tree: t, center: t.root).map(\.depth).max() == 6)
}

@Test func layoutOfEmptyRootIsEmpty() {
    let b = FileTreeBuilder(rootPath: "/r")
    b.appendChildren(of: b.root, entries: [DirEntry(name: "empty", kind: .directory)])
    let t = b.finish()
    #expect(SunburstLayout.layout(tree: t, center: t.root).isEmpty)
}

@Test func singleChildFillsFullCircle() {
    let b = FileTreeBuilder(rootPath: "/r")
    b.appendChildren(of: b.root, entries: [DirEntry(name: "f", kind: .file, allocatedSize: 5)])
    let t = b.finish()
    let s = SunburstLayout.layout(tree: t, center: t.root)
    #expect(s.count == 1 && s[0].startAngle == 0 && abs(s[0].endAngle - 2 * .pi) < 1e-9)
}

@Test func packagesNotExpandedUnlessRequested() {
    let b = FileTreeBuilder(rootPath: "/r")
    let app = b.appendChildren(of: b.root, entries: [DirEntry(name: "X.app", kind: .directory)])[0]
    b.appendChildren(of: app, entries: [DirEntry(name: "bin", kind: .file, allocatedSize: 9)])
    let t = b.finish()
    let plain = SunburstLayout.layout(tree: t, center: t.root)
    #expect(plain.count == 1 && plain[0].kind == .package)
    #expect(SunburstLayout.layout(tree: t, center: t.root, expandedPackages: [app]).contains { $0.depth == 2 })
}

@Test func virtualNodesExpand() {
    let t = abcTree()
    HiddenSpace.attach(HiddenSpaceBreakdown(purgeable: 30, otherVolumes: 20, stillHidden: 0), to: t)
    let segs = SunburstLayout.layout(tree: t, center: t.root)
    #expect(segs.filter { $0.kind == .virtual }.count == 3)
}
