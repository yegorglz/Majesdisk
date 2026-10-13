import AppKit
import MajesCore
import Quartz

/// Drives the shared Quick Look panel. AppDelegate (end of every responder chain) hands the panel to it.
@MainActor
final class QuickLookController: NSObject, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    static let shared = QuickLookController()
    private var url: URL?

    func toggle(model: ResultsModel) {
        guard let id = model.pointed, model.tree.virtualKind(id) == nil, model.hoveredSmallerObjects == nil else { return }
        toggle(path: model.tree.path(id))
    }

    func toggle(path: String) {
        guard let panel = QLPreviewPanel.shared() else { return }
        let next = URL(fileURLWithPath: path)
        if panel.isVisible, next == url { panel.orderOut(nil); return }
        url = next
        if panel.isVisible { panel.reloadData() } else { panel.makeKeyAndOrderFront(nil) }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! { url as NSURL? }
}

extension AppDelegate {
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = QuickLookController.shared
            panel.delegate = QuickLookController.shared
        }
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}
