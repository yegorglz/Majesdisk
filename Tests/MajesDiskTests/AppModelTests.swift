import Foundation
import Testing
@testable import MajesCore
@testable import MajesDisk

@MainActor private func tempTree() -> (FileTree, String) {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("majes-app-\(UUID().uuidString)").path
    try! FileManager.default.createDirectory(atPath: "\(d)/a", withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: "\(d)/a/x", contents: Data(count: 10_000))
    FileManager.default.createFile(atPath: "\(d)/y", contents: Data(count: 5_000))
    return (DiskScanner(options: ScanOptions(rootPath: d)).run()!, d)
}

@MainActor @Test func overviewKeepsResultsUntilForgotten() {
    let app = AppModel()
    let (tree, d) = tempTree()
    let r = ResultsModel(tree: tree, volume: nil, asAdministrator: false)
    app.present(r)
    app.showOverview()
    guard case .overview = app.screen else { Issue.record("expected overview"); return }
    #expect(app.cachedResults[d] === r)
    app.showResults(for: d)
    guard case .results(let shown) = app.screen else { Issue.record("expected results"); return }
    #expect(shown === r)
    app.forget(path: d)
    #expect(app.cachedResults[d] == nil)
}

@MainActor @Test func leavingResultsCancelsDeletionCountdown() async throws {
    let app = AppModel()
    let (tree, d) = tempTree()
    let r = ResultsModel(tree: tree, volume: nil, asAdministrator: false)
    app.present(r)
    r.addToCollector(tree.node(atPath: "\(d)/a")!)
    r.deletion.begin(model: r)
    try await Task.sleep(for: .milliseconds(300))
    app.showOverview()
    #expect(r.deletion.phase == .idle)
    try await Task.sleep(for: .seconds(6))
    #expect(FileManager.default.fileExists(atPath: "\(d)/a/x"))
}

@MainActor @Test func warnsAboutMissingAccessOnlyForScansThatHitProtectedFolders() {
    let app = AppModel()
    app.fullDiskAccess = false
    #expect(app.needsAccessWarning(for: "/"))
    #expect(app.needsAccessWarning(for: NSHomeDirectory()))
    #expect(app.needsAccessWarning(for: (NSHomeDirectory() as NSString).deletingLastPathComponent))
    #expect(!app.needsAccessWarning(for: "/tmp/x"))
    #expect(!app.needsAccessWarning(for: NSHomeDirectory() + "x"))
    app.fullDiskAccess = true
    #expect(!app.needsAccessWarning(for: "/"))
}

@MainActor private func waitForResults(_ app: AppModel) async throws -> ResultsModel {
    for _ in 0..<100 {
        if case .results(let r) = app.screen { return r }
        try await Task.sleep(for: .milliseconds(50))
    }
    throw CancellationError()
}

@MainActor @Test func scansSurviveARelaunchAndShowWhatGrew() async throws {
    let storeDir = FileManager.default.temporaryDirectory.appendingPathComponent("majes-store-\(UUID().uuidString)")
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("majes-grow-\(UUID().uuidString)").path
    try FileManager.default.createDirectory(atPath: "\(d)/sub", withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: "\(d)/sub/a", contents: Data(count: 10_000))
    defer { try? FileManager.default.removeItem(atPath: d); try? FileManager.default.removeItem(at: storeDir) }

    let first = AppModel(store: ScanStore(directory: storeDir))
    first.startScan(path: d, asAdministrator: false, warnAboutAccess: false)
    _ = try await waitForResults(first)

    // "Relaunch": a fresh model sees the saved scan and shows it without scanning.
    let second = AppModel(store: ScanStore(directory: storeDir))
    #expect(second.savedScans[d] != nil && second.hasResults(d))
    second.showResults(for: d)
    let reopened = try await waitForResults(second)
    #expect(reopened.tree.node(atPath: "\(d)/sub/a") != nil)

    // A rescan compares with the saved one.
    FileManager.default.createFile(atPath: "\(d)/sub/new", contents: Data(count: 50_000))
    second.startScan(path: d, asAdministrator: false, warnAboutAccess: false)
    var rescanned = try await waitForResults(second)
    for _ in 0..<100 where rescanned === reopened { try await Task.sleep(for: .milliseconds(50)); rescanned = try await waitForResults(second) }
    let sub = try #require(rescanned.tree.node(atPath: "\(d)/sub"))
    #expect(rescanned.delta(sub) == Int64(rescanned.tree.size(rescanned.tree.node(atPath: "\(d)/sub/new")!)))
    #expect(rescanned.delta(rescanned.tree.node(atPath: "\(d)/sub/a")!) == 0)

    second.forget(path: d)
    #expect(AppModel(store: ScanStore(directory: storeDir)).savedScans[d] == nil)
}

@MainActor @Test func savedFolderScansAreListedAfterRelaunch() throws {
    let storeDir = FileManager.default.temporaryDirectory.appendingPathComponent("majes-store-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: storeDir) }
    let b = FileTreeBuilder(rootPath: "/tmp/somewhere")
    try ScanStore(directory: storeDir).save(b.finish())
    #expect(AppModel(store: ScanStore(directory: storeDir)).folderList.contains("/tmp/somewhere"))
}
