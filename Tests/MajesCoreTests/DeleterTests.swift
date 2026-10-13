import Foundation
import Testing
@testable import MajesCore

private let allow: (String) -> ProtectionVerdict = { _ in .allowed }
private func exists(_ p: String) -> Bool { FileManager.default.fileExists(atPath: p) }

@Test func deleterRemovesFilesAndFolders() throws {
    let d = makeTempDir(); write("\(d)/f", bytes: 10)
    try FileManager.default.createDirectory(atPath: "\(d)/dir/sub", withIntermediateDirectories: true)
    write("\(d)/dir/sub/x", bytes: 10)
    let out = Deleter.delete(paths: ["\(d)/f", "\(d)/dir"], mode: .permanent, verdict: allow)
    #expect(out.map(\.failure) == [nil, nil])
    #expect(!exists("\(d)/f") && !exists("\(d)/dir"))
}

@Test func deleterRemovesSymlinkNotTarget() throws {
    let d = makeTempDir()
    try FileManager.default.createDirectory(atPath: "\(d)/target", withIntermediateDirectories: true)
    write("\(d)/target/keep", bytes: 10)
    try FileManager.default.createSymbolicLink(atPath: "\(d)/link", withDestinationPath: "\(d)/target")
    #expect(Deleter.delete(paths: ["\(d)/link"], mode: .permanent, verdict: allow)[0].failure == nil)
    #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: "\(d)/link")) == nil)
    #expect(exists("\(d)/target/keep"))
}

@Test func deleterRefusesProtectedPath() {
    let d = makeTempDir(); write("\(d)/f", bytes: 10)
    #expect(Deleter.delete(paths: ["\(d)/f"], mode: .permanent, verdict: { _ in .protected("x") })[0].failure == .protected("x"))
    #expect(exists("\(d)/f"))
}

@Test func deleterReportsMissing() {
    #expect(Deleter.delete(paths: ["/nonexistent-\(UUID())"], mode: .permanent, verdict: allow)[0].failure == .notFound)
}

@Test func deleterPermissionDenied() {
    guard getuid() != 0 else { return }
    let d = makeTempDir(); mkdir("\(d)/ro", 0o755); write("\(d)/ro/f", bytes: 10); chmod("\(d)/ro", 0o555)
    defer { chmod("\(d)/ro", 0o755) }
    #expect(Deleter.delete(paths: ["\(d)/ro/f"], mode: .permanent, verdict: allow)[0].failure == .permissionDenied)
    #expect(exists("\(d)/ro/f"))
}

@Test func deleterMovesToTrash() throws {
    let d = makeTempDir(); let name = "majes-trash-\(UUID().uuidString)"; write("\(d)/\(name)", bytes: 10)
    #expect(Deleter.delete(paths: ["\(d)/\(name)"], mode: .moveToTrash, verdict: allow)[0].failure == nil)
    #expect(!exists("\(d)/\(name)"))
    if let trash = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first {
        try? FileManager.default.removeItem(at: trash.appendingPathComponent(name))
    }
}
