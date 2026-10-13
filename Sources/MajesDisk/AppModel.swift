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
    var optionKeyDown = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var flagsMonitor: Any?
    @ObservationIgnored private var handledLaunchArgs = false

    init() {
        refreshVolumes()
        // Free space updates live, as in DaisyDisk.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in AppModel.shared.refreshVolumes() }
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            Task { @MainActor in AppModel.shared.optionKeyDown = event.modifierFlags.contains(.option) }
            return event
        }
    }

    func refreshVolumes() {
        let v = VolumeLister.mountedVolumes()
        if v != volumes { volumes = v }
    }

    func volume(forPath path: String) -> VolumeInfo? { volumes.first { $0.mountPath == path } }

    func toggleStar(_ path: String) {
        let s = StarredFolders()
        s.contains(path) ? s.remove(path) : s.add(path)
        starred = s.paths
    }

    func startScan(path: String, asAdministrator: Bool) {
        let session = ScanSession(rootPath: path, asAdministrator: asAdministrator, volume: volume(forPath: path))
        session.onFinish = { [weak self] state in
            guard let self else { return }
            switch state {
            case .finished(let tree): self.screen = .results(ResultsModel(tree: tree, volume: session.volume, asAdministrator: asAdministrator))
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

    func showOverview() {
        screen = .overview
        refreshVolumes()
    }

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
    func showSnapshots(for volume: VolumeInfo) {}
}
