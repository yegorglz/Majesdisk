import AppKit
import MajesCore
import SwiftUI

/// One context-menu command, shared by the map's NSMenu and the sidebar's SwiftUI menu.
struct NodeAction {
    let title: String
    let run: @MainActor () -> Void

    @MainActor static func actions(model: ResultsModel, id: NodeID) -> [NodeAction] {
        let tree = model.tree
        let kind = tree.virtualKind(id)
        var out: [NodeAction] = []
        if kind == nil {
            out.append(NodeAction(title: "Preview") { QuickLookController.shared.toggle(path: tree.path(id)) })
            out.append(NodeAction(title: "Reveal in Finder") { model.reveal(id) })
            out.append(NodeAction(title: "Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(tree.path(id), forType: .string)
            })
        }
        if kind == nil || kind == .purgeable {
            out.append(NodeAction(title: model.collector.contains(id) ? "Remove from Collector" : "Move to Collector") { model.toggleCollector(id) })
        }
        if tree.flags(id).contains(.package) {
            out.append(NodeAction(title: model.expandedPackages.contains(id) ? "Hide Package Contents" : "Show Package Contents") { model.togglePackage(id) })
        }
        if kind == nil, model.isContainer(id) || tree.flags(id).contains(.package) {
            out.append(NodeAction(title: "Rescan This Folder") { model.rescanFolder(id) })
        }
        return out
    }

    /// AppKit version for the map view.
    @MainActor static func menu(model: ResultsModel, id: NodeID) -> NSMenu {
        let menu = NSMenu()
        for a in actions(model: model, id: id) {
            let item = NSMenuItem(title: a.title, action: #selector(ClosureTarget.fire(_:)), keyEquivalent: "")
            let target = ClosureTarget(a.run)
            item.target = target
            item.representedObject = target  // keeps the target alive with the item
            menu.addItem(item)
        }
        return menu
    }
}

final class ClosureTarget: NSObject {
    let run: @MainActor () -> Void
    init(_ run: @escaping @MainActor () -> Void) { self.run = run }
    @MainActor @objc func fire(_ sender: Any?) { run() }
}

struct NodeContextMenu: View {
    let model: ResultsModel
    let id: NodeID

    var body: some View {
        ForEach(Array(NodeAction.actions(model: model, id: id).enumerated()), id: \.offset) { _, a in
            Button(a.title) { a.run() }
        }
    }
}
