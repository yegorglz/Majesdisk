import Foundation
import Testing
@testable import MajesCore

/// /r/a/b/c/movie.mov 60, /r/a/setup.dmg 20, /r/x/Tool.app (package, 30, with inner files), /r/notes.txt 5, /r/a/b/clip.mp4 1
private func spread() -> FileTree {
    let b = FileTreeBuilder(rootPath: "/r")
    let top = b.appendChildren(of: b.root, entries: [DirEntry(name: "a", kind: .directory), DirEntry(name: "x", kind: .directory),
                                                    DirEntry(name: "notes.txt", kind: .file, allocatedSize: 5)])
    let ab = b.appendChildren(of: top[0], entries: [DirEntry(name: "b", kind: .directory), DirEntry(name: "setup.dmg", kind: .file, allocatedSize: 20)])
    let abc = b.appendChildren(of: ab[0], entries: [DirEntry(name: "c", kind: .directory), DirEntry(name: "clip.mp4", kind: .file, allocatedSize: 1)])
    b.appendChildren(of: abc[0], entries: [DirEntry(name: "movie.mov", kind: .file, allocatedSize: 60)])
    let app = b.appendChildren(of: top[1], entries: [DirEntry(name: "Tool.app", kind: .directory)])[0]
    b.appendChildren(of: app, entries: [DirEntry(name: "bin", kind: .file, allocatedSize: 29), DirEntry(name: "res", kind: .file, allocatedSize: 1)])
    return b.finish()
}

@Test func largestFilesAcrossTheWholeTree() {
    let t = spread()
    #expect(t.largestFiles(under: t.root, limit: 3).map(t.name) == ["movie.mov", "Tool.app", "setup.dmg"])   // packages count as one item
    #expect(t.largestFiles(under: t.node(atPath: "/r/a")!, limit: 10).map(t.name) == ["movie.mov", "setup.dmg", "clip.mp4"])
}

@Test func largestFilesByKind() {
    let t = spread()
    #expect(t.largestFiles(under: t.root, limit: 10, kind: .video).map(t.name) == ["movie.mov", "clip.mp4"])
    #expect(t.largestFiles(under: t.root, limit: 10, kind: .archives).map(t.name) == ["setup.dmg"])
    #expect(t.largestFiles(under: t.root, limit: 10, kind: .apps).map(t.name) == ["Tool.app"])
    #expect(t.largestFiles(under: t.root, limit: 10, kind: .other).map(t.name) == ["notes.txt"])
    t.markDeleted(t.node(atPath: "/r/a/b")!)
    #expect(t.largestFiles(under: t.root, limit: 10, kind: .video).isEmpty)
}
