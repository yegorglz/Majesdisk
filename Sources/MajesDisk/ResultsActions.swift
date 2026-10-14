import Foundation
import MajesCore
import MajesMap

extension ResultsModel {
    /// ⌘R: rescans one folder in the background and splices the result into the existing tree.
    func rescanFolder(_ id: NodeID) {
        if id == tree.root || tree.virtualKind(id) != nil { rescanAll(); return }
        rescan([id])
    }

    /// Rescans folders one after another (also used after a delete that failed halfway).
    func rescan(_ ids: [NodeID]) {
        guard !isRescanning, !ids.isEmpty else { return }
        isRescanning = true
        let admin = asAdministrator
        Task {
            defer { isRescanning = false }
            for id in ids where !tree.isGone(id) {
                let path = tree.path(id)
                // Same mode as the original scan: as administrator through the helper, else in-process
                // with one reader on spinning disks.
                let fresh: FileTree?
                if admin {
                    do {
                        fresh = try await HelperScan().run(root: path, prompt: "MajesDisk wants to rescan this folder as administrator.") { _ in }
                    } catch {
                        fresh = nil
                        alert = AlertInfo(title: "Rescan failed", message: "\(error)")
                    }
                } else {
                    fresh = await Task.detached(priority: .userInitiated) {
                        let workers = ScanOptions.recommendedConcurrency(isSolidState: ScanSession.diskInfo(for: path)?.isSolidState)
                        return DiskScanner(options: ScanOptions(rootPath: path, maxConcurrency: workers)).run()
                    }.value
                }
                guard let fresh, !tree.isGone(id) else { continue }
                tree.replaceSubtree(of: id, with: fresh)
            }
            for c in collector.items where tree.isGone(c) { collector.remove(c) }
            leaveGoneCenter()
            history = NavigationHistory(start: center)  // older entries may point into the replaced subtrees
            hovered = nil; rowHovered = nil; selected = nil; hoveredSmallerObjects = nil; expandedSmallerObjects = nil
            treeVersion += 1
        }
    }

    /// ⇧⌘R: scans the whole disk or top folder again, the same way as before.
    func rescanAll() {
        AppModel.shared.startScan(path: tree.rootPath, asAdministrator: asAdministrator)
    }
}
