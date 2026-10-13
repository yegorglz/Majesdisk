import Foundation
import Testing
@testable import MajesCore

final class FakeReader: DirectoryReading, @unchecked Sendable {
    private let lock = NSLock()
    private let dirs: [String: DirectoryReadResult]
    private let delay: TimeInterval
    private var log: [String] = []
    init(_ dirs: [String: DirectoryReadResult], delay: TimeInterval = 0) { self.dirs = dirs; self.delay = delay }
    var requested: [String] { lock.withLock { log } }
    func read(path: String) -> DirectoryReadResult {
        lock.withLock { log.append(path) }
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        return dirs[path] ?? .failed(errno: ENOENT)
    }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock(); private var v = false
    var value: Bool { lock.withLock { v } }
    func set() { lock.withLock { v = true } }
}

@Test func scannerBuildsTreeFromReader() {
    let r = FakeReader(["/r": .entries([.init(name: "d", kind: .directory), .init(name: "f", kind: .file, allocatedSize: 10)]),
                        "/r/d": .entries([.init(name: "g", kind: .file, allocatedSize: 5)])])
    let t = DiskScanner(options: .init(rootPath: "/r", maxConcurrency: 4), reader: r).run()!
    #expect(t.size(t.root) == 15)
    #expect(t.children(t.root).map(t.name) == ["f", "d"])
}

@Test func scannerDoesNotDescendMountPointsOrSymlinks() {
    let r = FakeReader(["/r": .entries([.init(name: "dev", kind: .directory, isMountPoint: true),
                                        .init(name: "l", kind: .symlink, allocatedSize: 4096)])])
    let t = DiskScanner(options: .init(rootPath: "/r"), reader: r).run()!
    #expect(r.requested == ["/r"])
    #expect(t.flags(t.node(atPath: "/r/dev")!).contains(.mountPoint))
}

@Test func scannerFlagsRestrictedAndContinues() {
    let r = FakeReader(["/r": .entries([.init(name: "x", kind: .directory), .init(name: "f", kind: .file, allocatedSize: 7)]),
                        "/r/x": .failed(errno: EACCES)])
    let t = DiskScanner(options: .init(rootPath: "/r"), reader: r).run()!
    #expect(t.flags(t.node(atPath: "/r/x")!).contains(.restricted))
    #expect(t.size(t.root) == 7)
}

@Test func scannerJoinsRootSlash() {
    let r = FakeReader(["/": .entries([.init(name: "Users", kind: .directory)]), "/Users": .entries([])])
    _ = DiskScanner(options: .init(rootPath: "/"), reader: r).run()!
    #expect(Set(r.requested) == ["/", "/Users"])
}

@Test func scannerCancelsPromptly() {
    var dirs: [String: DirectoryReadResult] = ["/r": .entries((0..<200).map { .init(name: "d\($0)", kind: .directory) })]
    for i in 0..<200 { dirs["/r/d\(i)"] = .entries([]) }
    let r = FakeReader(dirs, delay: 0.01)
    let flag = Flag()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { flag.set() }
    let start = Date()
    #expect(DiskScanner(options: .init(rootPath: "/r", maxConcurrency: 2), reader: r).run(isCancelled: { flag.value }) == nil)
    #expect(Date().timeIntervalSince(start) < 0.5)
}

@Test func scannerReportsProgress() {
    let r = FakeReader(["/r": .entries([.init(name: "f", kind: .file, allocatedSize: 10)])])
    let seen = Flag()
    _ = DiskScanner(options: .init(rootPath: "/r"), reader: r).run(progress: { p in if p.files == 1 { seen.set() } })
    #expect(seen.value)
}

@Test func scannerMatchesDiskOnRealFolder() throws {
    let d = makeTempDir(); write("\(d)/a", bytes: 50_000)
    try FileManager.default.createDirectory(atPath: "\(d)/s/t", withIntermediateDirectories: true)
    write("\(d)/s/t/b", bytes: 9_000); _ = link("\(d)/a", "\(d)/s/a-hard")
    let t = DiskScanner(options: .init(rootPath: d)).run()!
    #expect(t.size(t.root) == allocated("\(d)/a") + allocated("\(d)/s/t/b"))
}

@Test func packagesAreFlagged() {
    #expect(PackageExtensions.isPackage(name: "Safari.app"))
    #expect(PackageExtensions.isPackage(name: "Photos Library.photoslibrary"))
    #expect(!PackageExtensions.isPackage(name: "src"))
    #expect(!PackageExtensions.isPackage(name: ".app"))
    #expect(ScanOptions.recommendedConcurrency(isSolidState: false) == 1)
    #expect(ScanOptions.recommendedConcurrency(isSolidState: nil) == 8)
}
