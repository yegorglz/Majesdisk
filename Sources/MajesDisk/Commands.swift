import MajesCore
import MajesMap
import SwiftUI

/// Menu bar commands; they act on the scan currently on screen.
struct MajesCommands: Commands {
    @MainActor private var results: ResultsModel? {
        if case .results(let r) = AppModel.shared.screen { return r }
        return nil
    }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Scan Folder…") { AppModel.shared.chooseFolderAndScan() }.keyboardShortcut("o")
            Divider()
            Button("Rescan Folder") { results?.perform(.rescanFolder) }.keyboardShortcut("r")
            Button("Rescan Disk") { results?.perform(.rescanAll) }.keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Forget Scan Results") { if let r = results { AppModel.shared.forget(path: r.tree.rootPath) } }
                .disabled(results == nil)
        }
        CommandMenu("Disk") {
            Button("Local Snapshots…") {
                let app = AppModel.shared
                if let v = results?.volume ?? app.volumes.first { app.showSnapshots(for: v) }
            }
        }
        CommandMenu("Go") {
            Button("Enclosing Folder") { results?.goUp() }.keyboardShortcut(.upArrow)
            Button("Back") { results?.goBack() }.keyboardShortcut("[")
            Button("Forward") { results?.goForward() }.keyboardShortcut("]")
            Button("Open Pointed Folder") { results?.perform(.enter) }
            Button("Move to Collector") { results?.perform(.toggleCollector) }.keyboardShortcut(.delete, modifiers: .command)
            Button("Quick Look") { results?.perform(.quickLook) }
            Divider()
            Button("Disks Overview") { AppModel.shared.showOverview() }
        }
    }
}
