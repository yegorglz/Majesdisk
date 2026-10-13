import Foundation
import Testing
@testable import MajesCore

@Test func roundTripPreservesTree() throws {
    let t = sampleTree()
    let h = t.appendVirtual(parent: t.root, name: "Hidden space", size: 5, kind: .hiddenSpace)
    let d = try TreeCodec.decode(TreeCodec.encode(t))
    #expect(d.rootPath == "/r" && d.nodeCount == t.nodeCount)
    #expect(d.size(d.root) == t.size(t.root))
    #expect(d.children(d.root).map(d.path) == t.children(t.root).map(t.path))
    #expect(d.virtualKind(h) == .hiddenSpace)
    #expect(d.flags(d.node(atPath: "/r/a")!) == t.flags(t.node(atPath: "/r/a")!))
    #expect(d.itemCount(d.root) == t.itemCount(t.root))
}

@Test func decodeRejectsBadMagic() {
    #expect(throws: TreeCodecError.badMagic) { try TreeCodec.decode(Data("NOPE0000".utf8)) }
}

@Test func decodeRejectsTruncated() {
    let data = TreeCodec.encode(sampleTree())
    #expect(throws: TreeCodecError.truncated) { try TreeCodec.decode(data.dropLast(3)) }
}
