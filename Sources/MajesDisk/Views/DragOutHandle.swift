import AppKit
import MajesCore
import SwiftUI

/// Makes a Collector row draggable; a drag that ends without being accepted anywhere
/// (dropped back on the map, the sidebar, the desktop…) takes the item out of the Collector.
struct DragOutHandle: NSViewRepresentable {
    let model: ResultsModel
    let id: NodeID

    func makeNSView(context: Context) -> DragOutView { DragOutView(model: model, id: id) }
    func updateNSView(_ v: DragOutView, context: Context) { v.model = model; v.id = id }
}

final class DragOutView: NSView, NSDraggingSource {
    weak var model: ResultsModel?
    var id: NodeID
    private var downPoint: NSPoint?

    init(model: ResultsModel, id: NodeID) {
        self.model = model; self.id = id
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func mouseDown(with event: NSEvent) {
        downPoint = event.locationInWindow
        // This view covers the row's label, so it also owns the row's double-click preview.
        if event.clickCount == 2, let model, model.tree.virtualKind(id) == nil {
            MainActor.assumeIsolated { QuickLookController.shared.toggle(path: model.tree.path(id)) }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downPoint else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 4 else { return }
        downPoint = nil
        let item = NSDraggingItem(pasteboardWriter: ResultsModel.dragURL(for: id) as NSURL)
        let image = NSImage(systemSymbolName: "doc", accessibilityDescription: nil) ?? NSImage()
        item.setDraggingFrame(CGRect(x: 0, y: 0, width: 24, height: 24), contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .copy : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard operation.isEmpty, let model else { return }
        MainActor.assumeIsolated { model.collector.remove(id) }
    }
}
