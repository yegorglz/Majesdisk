import AppKit
import CoreServices
import MajesCore
import Observation

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()
    let store: ScanStore
    /// Scans saved on disk by root path, with their date: they can be shown again after a relaunch.
    var savedScans: [String: Date] = [:]

    enum Screen { case overview, results(ResultsModel) }

    var screen: Screen = .overview
    var volumes: [VolumeInfo] = []
    var starred: [String] = StarredFolders().paths
    /// Folders scanned this session; clicking their icon stars them so they stay across launches.
    var recentFolders: [String] = []
    /// Starred folders, then this session's folders, then saved folder scans (newest first).
    var folderList: [String] {
        let saved = savedScans.filter { path, _ in !volumes.contains { $0.mountPath == path } }.sorted { $0.value > $1.value }.map(\.key)
        var seen = Set<String>()
        return (starred + recentFolders + saved).filter { seen.insert($0).inserted }
    }
    var optionKeyDown = false
    var fullDiskAccess = FullDiskAccess.isGranted()
    var snapshotsVolume: VolumeInfo?
    /// Finished scans by root path. Going back to the overview keeps them ("Show"); only Forget drops them.
    var cachedResults: [String: ResultsModel] = [:]
    /// Scans in progress by root path. They run from the overview rows, several at once.
    var scans: [String: ScanSession] = [:]
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored var warnedAboutAccess = false
    /// A saved scan being read from disk.
    var loadingPath: String?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var flagsMonitor: Any?
    @ObservationIgnored private var handledLaunchArgs = false

    init(store: ScanStore = ScanStore()) {
        self.store = store
        savedScans = store.saved()
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

    /// Without Full Disk Access, macOS stops a scan of the disk or the home folder with one privacy
    /// prompt per protected folder. Say so once per launch, before it happens.
    func needsAccessWarning(for path: String) -> Bool {
        let home = NSHomeDirectory()
        return fullDiskAccess != true && !warnedAboutAccess && (path == "/" || path == home || home.hasPrefix(path + "/"))
    }

    func startScan(path: String, asAdministrator: Bool, warnAboutAccess: Bool = true) {
        if warnAboutAccess, needsAccessWarning(for: path) {
            warnedAboutAccess = true
            let alert = NSAlert()
            alert.messageText = "Grant Full Disk Access first?"
            alert.informativeText = "Without it, macOS will ask about Desktop, Documents, Downloads and other apps' data one by one during the scan, and anything you decline is counted as hidden space."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Scan Anyway")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn: NSWorkspace.shared.open(FullDiskAccess.settingsURL); return
            case .alertSecondButtonReturn: break
            default: return
            }
        }
        guard scans[path] == nil else { return }
        leaveResults()
        screen = .overview
        if volume(forPath: path) == nil, !recentFolders.contains(path) { recentFolders.insert(path, at: 0) }
        let expected = cachedResults[path].map { $0.tree.size($0.tree.root) }
        let session = ScanSession(rootPath: path, asAdministrator: asAdministrator, volume: volume(forPath: path), store: store, expectedBytes: expected)
        session.onFinish = { [weak self] state in
            guard let self else { return }
            self.scans[path] = nil
            switch state {
            case .finished(let tree, let previous):
                self.savedScans[path] = Date()
                let results = ResultsModel(tree: tree, volume: session.volume, asAdministrator: asAdministrator, previous: previous)
                self.cachedResults[path]?.stopWatching()
                results.startWatching(since: session.startEventID)
                self.cachedResults[path] = results
                // Open it if the user is still on the overview; otherwise its row now says "Show".
                if case .overview = self.screen { self.present(results) }
                #if DEBUG
                self.applyDebugArguments(to: results)
                #endif
            case .failed(let message):
                let alert = NSAlert(); alert.messageText = "Couldn't scan “\((path as NSString).lastPathComponent)”"; alert.informativeText = message; alert.runModal()
            case .cancelled, .running: break
            }
        }
        scans[path] = session
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

    func hasResults(_ path: String) -> Bool { cachedResults[path] != nil || savedScans[path] != nil }

    /// Shows a scan from memory, or reads the saved one from disk (seconds for a whole disk).
    func showResults(for path: String) {
        leaveResults()
        if let r = cachedResults[path] { screen = .results(r); return }
        guard let date = savedScans[path] else { return }
        let store = store
        loadingPath = path
        Task {
            let tree = await Task.detached(priority: .userInitiated) { try? store.load(path) }.value
            loadingPath = nil
            guard let tree = tree ?? nil else { savedScans[path] = nil; return }
            let results = ResultsModel(tree: tree, volume: volume(forPath: path), asAdministrator: false, scannedAt: date)
            results.startWatching(since: FSEventStreamEventId(kFSEventStreamEventIdSinceNow))
            present(results)
        }
    }

    /// Edits made after a scan (deletes, folder rescans) are saved when the app quits.
    func saveEditedResults() {
        for r in cachedResults.values where r.isDirty { try? store.save(r.tree, scannedAt: r.scannedAt) }
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
        cachedResults[path]?.stopWatching()
        cachedResults[path] = nil
        store.remove(path)
        savedScans[path] = nil
    }

    #if DEBUG
    /// Debug: `--collect <path>` (repeatable) fills the Collector; `--delete-collected` starts Delete.
    private func applyDebugArguments(to results: ResultsModel) {
        let args = CommandLine.arguments
        for (i, a) in args.enumerated() where a == "--collect" && i + 1 < args.count {
            if let id = results.tree.node(atPath: args[i + 1]) { results.addToCollector(id) }
        }
        if args.contains("--delete-collected") { results.deletion.begin(model: results) }
        if let i = args.firstIndex(of: "--sidebar"), i + 1 < args.count,
           let mode = SidebarMode.allCases.first(where: { $0.rawValue.lowercased() == args[i + 1] }) { results.sidebarMode = mode }
    }
    #endif

    /// `--scan <path>` opens straight into a scan (handy for testing).
    func handleLaunchArguments() {
        guard !handledLaunchArgs else { return }
        handledLaunchArgs = true
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--scan"), i + 1 < args.count {
            startScan(path: (args[i + 1] as NSString).expandingTildeInPath, asAdministrator: args.contains("--admin"), warnAboutAccess: false)
        }
    }
}

extension AppModel {
    func showSnapshots(for volume: VolumeInfo) { snapshotsVolume = volume }
}
