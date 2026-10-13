import Foundation
import MajesCore
import MajesMap

extension ResultsModel {
    /// ⌘R: rescans one folder in the background and splices the result into the existing tree.
    func rescanFolder(_ id: NodeID) {
        if id == tree.root || tree.virtualKind(id) != nil { rescanAll(); return }
        guard !isRescanning else { return }
        isRescanning = true
        let path = tree.path(id)
        Task {
            let fresh = await Task.detached(priority: .userInitiated) { DiskScanner(options: ScanOptions(rootPath: path)).run() }.value
            isRescanning = false
            guard let fresh, !tree.flags(id).contains(.deleted) else { return }
            tree.replaceSubtree(of: id, with: fresh)
            for c in collector.items where tree.flags(c).contains(.deleted) { collector.remove(c) }
            history = NavigationHistory(start: center)  // older entries may point into the replaced subtree
            hovered = nil; rowHovered = nil; selected = nil; hoveredSmallerObjects = nil; expandedSmallerObjects = nil
            treeVersion += 1
        }
    }

    /// ⇧⌘R: scans the whole disk or top folder again, the same way as before.
    func rescanAll() {
        AppModel.shared.startScan(path: tree.rootPath, asAdministrator: asAdministrator)
    }
}
