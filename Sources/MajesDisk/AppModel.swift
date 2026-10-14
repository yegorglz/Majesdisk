import AppKit
import MajesCore
import Observation

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    enum Screen { case overview, scanning(ScanSession), results(ResultsModel) }

    var screen: Screen = .overview
    var volumes: [VolumeInfo] = []
    var starred: [String] = StarredFolders().paths
    /// Folders scanned this session; clicking their icon stars them so they stay across launches.
    var recentFolders: [String] = []
    var folderList: [String] { starred + recentFolders.filter { !starred.contains($0) } }
    var optionKeyDown = false
    var fullDiskAccess = FullDiskAccess.isGranted()
    var snapshotsVolume: VolumeInfo?
    /// Finished scans by root path. Going back to the overview keeps them ("Show"); only Forget drops them.
    var cachedResults: [String: ResultsModel] = [:]
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var flagsMonitor: Any?
    @ObservationIgnored private var handledLaunchArgs = false

    init() {
        // Admin-scan work folders left behind by a quit mid-scan.
        let tmp = FileManager.default.temporaryDirectory
        for name in (try? FileManager.default.contentsOfDirectory(atPath: tmp.path)) ?? [] where name.hasPrefix("MajesDisk-") {
            try? FileManager.default.removeItem(at: tmp.appendingPathComponent(name))
        }
        volumes = VolumeLister.mountedVolumes()
        // Free space updates live, as in DaisyDisk.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in AppModel.shared.refreshVolumes() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in AppModel.shared.fullDiskAccess = FullDiskAccess.isGranted() }
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            Task { @MainActor in AppModel.shared.optionKeyDown = event.modifierFlags.contains(.option) }
            return event
        }
    }

    /// Off the main thread, so a stalled network mount can't freeze the UI; one refresh at a time.
    func refreshVolumes() {
        guard !refreshing else { return }
        refreshing = true
        Task {
            let v = await Task.detached(priority: .utility) { VolumeLister.mountedVolumes() }.value
            if v != volumes { volumes = v }
            refreshing = false
        }
    }

    func volume(forPath path: String) -> VolumeInfo? { volumes.first { $0.mountPath == path } }

    func toggleStar(_ path: String) {
        let s = StarredFolders()
        s.contains(path) ? s.remove(path) : s.add(path)
        starred = s.paths
    }

    func startScan(path: String, asAdministrator: Bool) {
        leaveResults()
        if volume(forPath: path) == nil, !recentFolders.contains(path) { recentFolders.insert(path, at: 0) }
        let session = ScanSession(rootPath: path, asAdministrator: asAdministrator, volume: volume(forPath: path))
        session.onFinish = { [weak self] state in
            guard let self else { return }
            switch state {
            case .finished(let tree):
                let results = ResultsModel(tree: tree, volume: session.volume, asAdministrator: asAdministrator)
                self.present(results)
                #if DEBUG
                self.applyDebugArguments(to: results)
                #endif
            case .failed(let message):
                self.screen = .overview
                let alert = NSAlert(); alert.messageText = "Scan failed"; alert.informativeText = message; alert.runModal()
            case .cancelled, .running: self.screen = .overview
            }
        }
        screen = .scanning(session)
        session.start()
    }

    func chooseFolderAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = "Scan"
        if panel.runModal() == .OK, let url = panel.url { startScan(path: url.path, asAdministrator: false) }
    }

    /// Full Disk Access only applies to a fresh process.
    static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-n", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }

    func present(_ results: ResultsModel) {
        cachedResults[results.tree.rootPath] = results
        screen = .results(results)
    }

    func showResults(for path: String) {
        guard let r = cachedResults[path] else { return }
        leaveResults()
        screen = .results(r)
    }

    /// Leaving a results screen aborts a pending delete: its Cancel button would no longer be visible.
    private func leaveResults() {
        if case .results(let r) = screen { r.deletion.cancel() }
    }

    func showOverview() {
        leaveResults()
        screen = .overview
        refreshVolumes()
    }

    /// Frees a scan's memory; its row goes back to "Scan".
    func forget(path: String) {
        if case .results(let r) = screen, r.tree.rootPath == path { showOverview() }
        cachedResults[path]?.deletion.cancel()
        cachedResults[path] = nil
    }

    #if DEBUG
    /// Debug: `--collect <path>` (repeatable) fills the Collector; `--delete-collected` starts Delete.
    private func applyDebugArguments(to results: ResultsModel) {
        let args = CommandLine.arguments
        for (i, a) in args.enumerated() where a == "--collect" && i + 1 < args.count {
            if let id = results.tree.node(atPath: args[i + 1]) { results.addToCollector(id) }
        }
        if args.contains("--delete-collected") { results.deletion.begin(model: results) }
    }
    #endif

    /// `--scan <path>` opens straight into a scan (handy for testing).
    func handleLaunchArguments() {
        guard !handledLaunchArgs else { return }
        handledLaunchArgs = true
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--scan"), i + 1 < args.count {
            startScan(path: (args[i + 1] as NSString).expandingTildeInPath, asAdministrator: args.contains("--admin"))
        }
    }
}

extension AppModel {
    func showSnapshots(for volume: VolumeInfo) { snapshotsVolume = volume }
}
