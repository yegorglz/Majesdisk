import Foundation
import Testing
@testable import MajesCore
@testable import MajesDisk

/// root: big file + 300 tiny files (merged into "smaller objects")
@MainActor private func smallTree() -> FileTree {
    let b = FileTreeBuilder(rootPath: "/r")
    b.appendChildren(of: b.root, entries: [DirEntry(name: "big", kind: .file, allocatedSize: 10_000)]
        + (0..<300).map { DirEntry(name: "t\($0)", kind: .file, allocatedSize: 1) })
    return b.finish()
}

@MainActor @Test func collectorKeyRefusesSmallerObjects() {
    let tree = smallTree()
    let m = ResultsModel(tree: tree, volume: nil, asAdministrator: false)
    m.selected = tree.node(atPath: "/r/big")
    m.hoveredSmallerObjects = SmallerObjectsRef(parent: tree.root, start: 1)
    m.perform(.toggleCollector)
    #expect(m.collector.items.isEmpty)
    #expect(m.alert != nil)
}

@MainActor @Test func pickingASidebarRowKeepsThatFolderAndPointsAtTheRow() {
    let b = FileTreeBuilder(rootPath: "/r")
    let dir = b.appendChildren(of: b.root, entries: [DirEntry(name: "d", kind: .directory), DirEntry(name: "f", kind: .file, allocatedSize: 1)])[0]
    let kid = b.appendChildren(of: dir, entries: [DirEntry(name: "k", kind: .file, allocatedSize: 5)])[0]
    let m = ResultsModel(tree: b.finish(), volume: nil, asAdministrator: false)
    m.hovered = dir                      // pointing at folder d in the map shows its contents
    #expect(m.sidebarFolder == dir)
    m.selectFromSidebar(kid)             // the user then clicks a row in that list
    #expect(m.sidebarFolder == dir && m.hovered == nil && m.pointed == kid)
    m.perform(.toggleCollector)
    #expect(m.collector.items == [kid])
    m.goUp(); m.enter(dir); m.goUp()
    #expect(m.sidebarFolder == m.center)
}
