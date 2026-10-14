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

@MainActor @Test func commandClickInSidebarRevealsInsteadOfSelecting() {
    let b = FileTreeBuilder(rootPath: "/r")
    let f = b.appendChildren(of: b.root, entries: [DirEntry(name: "f", kind: .file, allocatedSize: 1)])[0]
    let m = ResultsModel(tree: b.finish(), volume: nil, asAdministrator: false)
    var revealed: [URL] = []
    ResultsModel.revealInFinder = { revealed.append($0) }
    defer { ResultsModel.revealInFinder = ResultsModel.defaultReveal }
    m.sidebarSelectionChanged(f, commandKey: true)
    #expect(revealed == [URL(fileURLWithPath: "/r/f")] && m.selected == nil)
    m.sidebarSelectionChanged(f, commandKey: false)
    #expect(m.selected == f)
    m.sidebarSelectionChanged(nil, commandKey: true)   // ⌘-click on the selected row deselects in List terms
    #expect(revealed.count == 2 && m.selected == f)
}

@MainActor @Test func failedAdminRescanShowsAlert() async throws {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("majes-rs-\(UUID().uuidString)").path
    try FileManager.default.createDirectory(atPath: "\(d)/sub", withIntermediateDirectories: true)
    let tree = DiskScanner(options: ScanOptions(rootPath: d)).run()!
    let m = ResultsModel(tree: tree, volume: nil, asAdministrator: true)
    Helper.elevate = false
    Helper.pathOverride = "/nonexistent/majes-helper"
    defer { Helper.elevate = true; Helper.pathOverride = nil }
    m.rescanFolder(tree.node(atPath: "\(d)/sub")!)
    for _ in 0..<50 where m.isRescanning { try await Task.sleep(for: .milliseconds(100)) }
    #expect(!m.isRescanning)
    #expect(m.alert?.title == "Rescan failed")
}

@MainActor @Test func historySkipsDeletedFolders() {
    let b = FileTreeBuilder(rootPath: "/r")
    let ids = b.appendChildren(of: b.root, entries: [DirEntry(name: "a", kind: .directory), DirEntry(name: "b", kind: .directory)])
    let inner = b.appendChildren(of: ids[0], entries: [DirEntry(name: "deep", kind: .directory)])[0]
    b.appendChildren(of: inner, entries: [DirEntry(name: "x", kind: .file, allocatedSize: 5)])
    b.appendChildren(of: ids[1], entries: [DirEntry(name: "y", kind: .file, allocatedSize: 5)])
    let m = ResultsModel(tree: b.finish(), volume: nil, asAdministrator: false)
    m.enter(ids[1]); m.goUp(); m.enter(ids[0]); m.enter(inner); m.goUp(); m.goUp()   // history: r b r a deep a [r]
    m.tree.markDeleted(ids[0])
    m.goBack()
    #expect(m.center == m.tree.root)      // "a" and "a/deep" are gone; lands on the previous live folder
    m.goBack()
    #expect(m.center == ids[1])
    m.goForward(); m.goForward()
    #expect(!m.tree.isGone(m.center))
}

@MainActor @Test func halfFailedFolderDeleteRescansThatFolder() async throws {
    guard getuid() != 0 else { return }
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("majes-pd-\(UUID().uuidString)").path
    try FileManager.default.createDirectory(atPath: "\(d)/folder/ro", withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: "\(d)/folder/a", contents: Data(count: 50_000))
    FileManager.default.createFile(atPath: "\(d)/folder/ro/locked", contents: Data(count: 9_000))
    chmod("\(d)/folder/ro", 0o555)
    defer { chmod("\(d)/folder/ro", 0o755); try? FileManager.default.removeItem(atPath: d) }
    let m = ResultsModel(tree: DiskScanner(options: ScanOptions(rootPath: d)).run()!, volume: nil, asAdministrator: false)
    m.addToCollector(m.tree.node(atPath: "\(d)/folder")!)
    await m.deleteCollected()
    for _ in 0..<50 where m.isRescanning { try await Task.sleep(for: .milliseconds(50)) }
    #expect(!FileManager.default.fileExists(atPath: "\(d)/folder/a"))
    #expect(m.tree.node(atPath: "\(d)/folder/a") == nil)                 // the map matches the disk again
    #expect(m.tree.node(atPath: "\(d)/folder/ro/locked") != nil)
    #expect(m.alert?.title == "Some items couldn't be deleted")
}

@MainActor @Test func sidebarFoldsTinyItemsLikeTheMap() {
    let tree = smallTree()
    let m = ResultsModel(tree: tree, volume: nil, asAdministrator: false)
    #expect(m.sidebarItems.map(tree.name) == ["big"])
    #expect(m.sidebarFold == 1)
    m.expandSmallerObjects(SmallerObjectsRef(parent: tree.root, start: 1))
    #expect(m.sidebarItems.count == 300 && m.sidebarFold == nil)
}

@MainActor @Test func compactionKeepsWhatTheScreenShows() {
    let b = FileTreeBuilder(rootPath: "/r")
    let dirs = b.appendChildren(of: b.root, entries: [DirEntry(name: "junk", kind: .directory), DirEntry(name: "keep", kind: .directory)])
    b.appendChildren(of: dirs[0], entries: (0..<50).map { DirEntry(name: "j\($0)", kind: .file, allocatedSize: 1) })
    let kept = b.appendChildren(of: dirs[1], entries: [DirEntry(name: "k", kind: .file, allocatedSize: 9)])[0]
    let m = ResultsModel(tree: b.finish(), volume: nil, asAdministrator: false)
    m.enter(dirs[1])
    m.addToCollector(kept)
    m.tree.markDeleted(dirs[0])          // 51 dead nodes vs 4 live
    m.compactIfNeeded()
    #expect(m.tree.nodeCount == 3)
    #expect(m.tree.path(m.center) == "/r/keep")
    #expect(m.collector.items.map(m.tree.path) == ["/r/keep/k"])
}

@MainActor @Test func mapDescribesItselfToVoiceOver() {
    let tree = smallTree()
    let m = ResultsModel(tree: tree, volume: nil, asAdministrator: false)
    let v = SunburstNSView()
    v.model = m
    v.refresh()
    #expect(v.isAccessibilityElement())
    #expect(v.accessibilityLabel()?.contains("r") == true)
    m.hovered = tree.node(atPath: "/r/big")
    v.refresh()
    #expect(v.accessibilityLabel()?.contains("big") == true)
}
