import Foundation
import Testing
@testable import MajesCore

@Test func readerReportsKindsSizesLinksAndClones() throws {
    let d = makeTempDir()
    write("\(d)/big", bytes: 1_000_000)
    try FileManager.default.createDirectory(atPath: "\(d)/sub", withIntermediateDirectories: false)
    try FileManager.default.createSymbolicLink(atPath: "\(d)/link", withDestinationPath: "\(d)/sub")
    #expect(link("\(d)/big", "\(d)/hard") == 0)
    #expect(clonefile("\(d)/big", "\(d)/clone", 0) == 0)
    guard case .entries(let es) = BulkDirectoryReader().read(path: d) else { Issue.record("failed"); return }
    let by = Dictionary(uniqueKeysWithValues: es.map { ($0.name, $0) })
    #expect(Set(by.keys) == ["big", "sub", "link", "hard", "clone"])
    #expect(by["sub"]?.kind == .directory && by["link"]?.kind == .symlink)
    #expect(by["big"]?.allocatedSize == allocated("\(d)/big"))
    #expect(by["big"]?.linkCount == 2 && by["hard"]?.fileID == by["big"]?.fileID)
    #expect(by["clone"]?.cloneID == by["big"]?.cloneID && by["clone"]!.cloneRefCount >= 2)
    #expect(by["sub"]?.isMountPoint == false)
}

@Test func readerReadsLargeDirectory() {
    let d = makeTempDir()
    for i in 0..<5_000 { write("\(d)/file-with-a-fairly-long-name-\(i).txt", bytes: 1) }
    guard case .entries(let es) = BulkDirectoryReader().read(path: d) else { Issue.record("failed"); return }
    #expect(es.count == 5_000)
}

@Test func readerHandlesUnicodeNames() {
    let d = makeTempDir(); let name = "Фото 🌼 café " + String(repeating: "x", count: 200)
    write("\(d)/\(name)", bytes: 10)
    guard case .entries(let es) = BulkDirectoryReader().read(path: d) else { Issue.record("failed"); return }
    #expect(es.map { nfc($0.name) } == [nfc(name)])
}

@Test func readerReportsPermissionDenied() {
    let d = makeTempDir(); mkdir("\(d)/locked", 0o000); defer { chmod("\(d)/locked", 0o755) }
    guard getuid() != 0 else { return }
    guard case .failed(let e) = BulkDirectoryReader().read(path: "\(d)/locked") else { Issue.record("expected failure"); return }
    #expect(e == EACCES)
}

@Test func readerReportsMissing() {
    guard case .failed(let e) = BulkDirectoryReader().read(path: "/nonexistent-\(UUID())") else { Issue.record("x"); return }
    #expect(e == ENOENT)
}

@Test func mountPointsAreFlagged() {
    guard case .entries(let es) = BulkDirectoryReader().read(path: "/") else { Issue.record("x"); return }
    #expect(es.first { $0.name == "dev" }?.isMountPoint == true)
    #expect(es.first { $0.name == "Users" }?.isMountPoint == false)
}
