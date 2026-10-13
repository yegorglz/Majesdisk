import Foundation
import Testing
@testable import MajesCore

func sampleTree() -> FileTree {
    let b = FileTreeBuilder(rootPath: "/r")
    let top = b.appendChildren(of: b.root, entries: [
        DirEntry(name: "a", kind: .directory),
        DirEntry(name: "f", kind: .file, allocatedSize: 100),
        DirEntry(name: "e", kind: .directory)])
    b.appendChildren(of: top[0], entries: [DirEntry(name: "g", kind: .file, allocatedSize: 300)])
    return b.finish()
}

@Test func aggregatesAndSorts() {
    let t = sampleTree()
    #expect(t.size(t.root) == 400)
    #expect(t.children(t.root).map(t.name) == ["a", "f", "e"])
    #expect(t.path(t.children(t.root)[0]) == "/r/a")
    #expect(t.itemCount(t.root) == 4)
    #expect(t.node(atPath: "/r/a/g").map(t.size) == 300)
}

@Test func hardLinksAndClonesCountOnce() {
    let b = FileTreeBuilder(rootPath: "/r")
    let ids = b.appendChildren(of: b.root, entries: [
        DirEntry(name: "a", kind: .file, allocatedSize: 1000, fileID: 7, linkCount: 2, cloneID: 7, cloneRefCount: 2),
        DirEntry(name: "h", kind: .file, allocatedSize: 1000, fileID: 7, linkCount: 2, cloneID: 7, cloneRefCount: 2),
        DirEntry(name: "b", kind: .file, allocatedSize: 1000, fileID: 8, linkCount: 1, cloneID: 7, cloneRefCount: 2)])
    let t = b.finish()
    #expect(t.size(t.root) == 1000)
    #expect(ids.filter { t.flags($0).contains(.secondaryLink) }.count == 2)
}

@Test func markDeletedUpdatesAncestorsAndResorts() {
    let t = sampleTree()
    let a = t.node(atPath: "/r/a")!
    t.markDeleted(t.node(atPath: "/r/a/g")!)
    #expect(t.size(t.root) == 100)
    #expect(t.size(a) == 0)
    #expect(t.children(t.root).map(t.name) == ["f", "a", "e"])
}

@Test func virtualNodesAddToParent() {
    let t = sampleTree()
    let h = t.appendVirtual(parent: t.root, name: "Hidden space", size: 600, kind: .hiddenSpace)
    #expect(t.size(t.root) == 1000)
    #expect(t.children(t.root).first == h)
    #expect(t.virtualKind(h) == .hiddenSpace)
}

@Test func rootPathSlashJoinsCleanly() {
    let b = FileTreeBuilder(rootPath: "/")
    b.appendChildren(of: b.root, entries: [DirEntry(name: "Users", kind: .directory)])
    let t = b.finish()
    #expect(t.path(t.children(t.root)[0]) == "/Users")
    #expect(t.node(atPath: "/Users") != nil)
    #expect(t.node(atPath: "/") == t.root)
}

@Test func replaceSubtreeSplicesAndAdjustsSizes() {
    let t = sampleTree()
    let a = t.node(atPath: "/r/a")!
    let b = FileTreeBuilder(rootPath: "/r/a")
    b.appendChildren(of: b.root, entries: [DirEntry(name: "x", kind: .file, allocatedSize: 50), DirEntry(name: "y", kind: .file, allocatedSize: 25)])
    t.replaceSubtree(of: a, with: b.finish())
    #expect(t.size(a) == 75)
    #expect(t.size(t.root) == 175)
    #expect(t.children(a).map(t.name) == ["x", "y"])
    #expect(t.node(atPath: "/r/a/g") == nil)
    #expect(t.node(atPath: "/r/a/x") != nil)
    #expect(t.itemCount(t.root) == 5)
    #expect(t.children(t.root).map(t.name) == ["f", "a", "e"])
}
