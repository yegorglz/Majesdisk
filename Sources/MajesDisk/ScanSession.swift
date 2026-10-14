import Foundation
import MajesCore
import Observation

/// Thread-safe flag shared between the UI and scanner threads.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock(); private var flag = false
    var value: Bool { lock.withLock { flag } }
    func set() { lock.withLock { flag = true } }
}

@MainActor @Observable
final class ScanSession {
    /// `previous` is the last saved scan of the same folder, for "what grew" comparisons.
    enum State { case running, finished(FileTree, previous: FileTree?), failed(String), cancelled }
    let rootPath: String
    let asAdministrator: Bool
    let volume: VolumeInfo?
    var progress = ScanProgress()
    var state: State = .running
    @ObservationIgnored var onFinish: ((State) -> Void)?
    @ObservationIgnored let cancelFlag = CancelFlag()
    @ObservationIgnored var helperScan: HelperScan?

    let store: ScanStore?

    init(rootPath: String, asAdministrator: Bool, volume: VolumeInfo?, store: ScanStore? = nil) {
        self.rootPath = rootPath; self.asAdministrator = asAdministrator; self.volume = volume; self.store = store
    }

    func start() {
        if asAdministrator { startAdministratorScan(); return }
        let root = rootPath, flag = cancelFlag
        Task.detached(priority: .userInitiated) { [weak self] in
            let concurrency = ScanOptions.recommendedConcurrency(isSolidState: Self.diskInfo(for: root)?.isSolidState)
            let tree = DiskScanner(options: ScanOptions(rootPath: root, maxConcurrency: concurrency)).run(
                progress: { p in Task { @MainActor in self?.progress = p } },
                isCancelled: { flag.value })
            guard let tree else { await self?.finish(.cancelled); return }
            await self?.completed(tree)
        }
    }

    func cancel() {
        cancelFlag.set()
        cancelAdministratorScan()
    }

    /// Attaches hidden space for whole-volume scans, saves the scan (keeping the previous one for
    /// comparison), then hands the tree to the UI. All before anyone can edit the tree.
    func completed(_ tree: FileTree) async {
        let root = rootPath, store = store
        if let volume, volume.mountPath == rootPath {
            await Task.detached(priority: .userInitiated) {
                let other = Self.diskInfo(for: root).map {
                    APFSInfo.otherVolumesBytes(containers: APFSInfo.containers(), scanned: $0, isRootScan: root == "/")
                } ?? 0
                if let b = HiddenSpace.compute(usedBytes: volume.usedBytes, scannedBytes: tree.size(tree.root),
                                               purgeableBytes: volume.purgeableBytes, otherVolumesBytes: other) {
                    HiddenSpace.attach(b, to: tree)
                }
            }.value
        }
        let previous: FileTree? = await Task.detached(priority: .userInitiated) {
            let previous = try? store?.load(root)
            try? store?.save(tree)
            return previous ?? nil
        }.value
        finish(.finished(tree, previous: previous))
    }

    func finish(_ s: State) {
        if case .running = state {} else { return }
        state = s
        onFinish?(s)
    }

    nonisolated static func diskInfo(for path: String) -> DiskInfoRecord? {
        let mount = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeURLKey]))?.volume?.path ?? path
        return APFSInfo.diskInfo(mountPath: mount)
    }
}
