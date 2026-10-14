import Foundation
import Testing
@testable import MajesCore

@Test func savedScansSurviveAndCanBeForgotten() throws {
    let dir = URL(fileURLWithPath: makeTempDir())
    let store = ScanStore(directory: dir)
    let t = sampleTree()
    try store.save(t, scannedAt: Date(timeIntervalSince1970: 1_000))
    let again = ScanStore(directory: dir)
    #expect(again.saved() == ["/r": Date(timeIntervalSince1970: 1_000)])
    let loaded = try #require(try again.load("/r"))
    #expect(loaded.size(loaded.root) == 400 && loaded.node(atPath: "/r/a/g") != nil)
    again.remove("/r")
    #expect(ScanStore(directory: dir).saved().isEmpty)
    #expect(try ScanStore(directory: dir).load("/r") == nil)
}

@Test func savedScansRememberTheirTotal() throws {
    let store = ScanStore(directory: URL(fileURLWithPath: makeTempDir()))
    try store.save(sampleTree())
    #expect(store.savedSize("/r") == 400)
}
