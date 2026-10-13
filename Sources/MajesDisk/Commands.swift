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
            Button("Forget Scan Results") { AppModel.shared.showOverview() }
        }
        CommandMenu("Go") {
            Button("Enclosing Folder") { results?.goUp() }.keyboardShortcut(.upArrow)
            Button("Back") { results?.goBack() }.keyboardShortcut("[")
            Button("Forward") { results?.goForward() }.keyboardShortcut("]")
            Button("Open Pointed Folder") { results?.perform(.enter) }
            Divider()
            Button("Disks Overview") { AppModel.shared.showOverview() }
        }
    }
}
