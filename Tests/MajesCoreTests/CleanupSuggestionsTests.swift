import Foundation
import Testing
@testable import MajesCore

@Test func suggestsKnownRegenerableFolders() {
    let mb: UInt64 = 1_000_000
    let b = FileTreeBuilder(rootPath: "/r")
    let users = b.appendChildren(of: b.root, entries: [DirEntry(name: "Users", kind: .directory)])[0]
    let home = b.appendChildren(of: users, entries: [DirEntry(name: "u", kind: .directory)])[0]
    let hk = b.appendChildren(of: home, entries: [DirEntry(name: "Library", kind: .directory), DirEntry(name: "code", kind: .directory),
                                                 DirEntry(name: ".Trash", kind: .directory)])
    b.appendChildren(of: hk[2], entries: [DirEntry(name: "junk", kind: .file, allocatedSize: 10 * mb)])   // under the 50 MB floor
    let dev = b.appendChildren(of: hk[0], entries: [DirEntry(name: "Developer", kind: .directory)])[0]
    let xcode = b.appendChildren(of: dev, entries: [DirEntry(name: "Xcode", kind: .directory)])[0]
    let dd = b.appendChildren(of: xcode, entries: [DirEntry(name: "DerivedData", kind: .directory)])[0]
    b.appendChildren(of: dd, entries: [DirEntry(name: "build", kind: .file, allocatedSize: 50 * mb)])
    let proj = b.appendChildren(of: hk[1], entries: [DirEntry(name: "site", kind: .directory)])[0]
    let nm = b.appendChildren(of: proj, entries: [DirEntry(name: "node_modules", kind: .directory)])[0]
    let inner = b.appendChildren(of: nm, entries: [DirEntry(name: "dep", kind: .directory), DirEntry(name: "big.js", kind: .file, allocatedSize: 70 * mb)])[0]
    let innerNM = b.appendChildren(of: inner, entries: [DirEntry(name: "node_modules", kind: .directory)])[0]
    b.appendChildren(of: innerNM, entries: [DirEntry(name: "x.js", kind: .file, allocatedSize: 60 * mb)])
    let t = b.finish()

    let s = CleanupSuggestions.find(in: t)
    #expect(s.map { t.path($0.node) } == ["/r/Users/u/code/site/node_modules", "/r/Users/u/Library/Developer/Xcode/DerivedData"])
    #expect(s.first?.title == "node_modules in site")            // nested node_modules isn't listed twice
    #expect(s.last?.title == "Xcode build data" && !s.last!.note.isEmpty)
    #expect(t.size(s.last!.node) == 50 * mb)
}
