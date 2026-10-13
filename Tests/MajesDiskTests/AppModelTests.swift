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
