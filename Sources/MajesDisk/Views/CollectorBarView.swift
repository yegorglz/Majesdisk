import MajesCore
import SwiftUI

/// Drag target at the bottom of the window. Items stay intact until Delete and a 5-second countdown.
struct CollectorBarView: View {
    let model: ResultsModel
    @State private var showList = false
    @State private var targeted = false

    var body: some View {
        let items = model.collector.items
        HStack(spacing: 12) {
            Button { if !items.isEmpty { showList.toggle() } } label: {
                HStack(spacing: 10) {
                    Image(systemName: items.isEmpty ? "tray" : "tray.full.fill").font(.title2)
                    if items.isEmpty {
                        Text("Drag files here to delete").foregroundStyle(.secondary)
                    } else {
                        Text("\(items.count) item\(items.count == 1 ? "" : "s") · \(ByteFormat.string(model.collector.totalSize(in: model.tree)))")
                            .font(.headline.monospacedDigit())
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showList, arrowEdge: .top) { CollectorListView(model: model) }
            Spacer()
            switch model.deletion.phase {
            case .countdown(let n):
                Text("Deleting in \(n)…").foregroundStyle(.secondary).monospacedDigit()
                Button("Cancel") { model.deletion.cancel() }.keyboardShortcut(.cancelAction)
            case .deleting:
                ProgressView().controlSize(.small)
                Text("Deleting…").foregroundStyle(.secondary)
            case .idle:
                Button(role: .destructive) { model.deletion.begin(model: model) } label: {
                    Text(model.deleteMode == .moveToTrash ? "Move to Trash" : "Delete")
                }
                .tint(.red).buttonStyle(.borderedProminent)
                .disabled(items.isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(targeted ? Color.accentColor.opacity(0.2) : Color.clear)
        .dropDestination(for: URL.self) { urls, _ in
            let ids = urls.compactMap(model.node(forDropped:))
            ids.forEach(model.addToCollector)
            return !ids.isEmpty
        } isTargeted: { targeted = $0 }
    }
}

/// Expanded Collector: preview with Space, remove with ×.
struct CollectorListView: View {
    let model: ResultsModel

    var body: some View {
        List(model.collector.items, id: \.self) { id in
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Circle().fill(Color(nsColor: model.color(for: id).nsColor)).frame(width: 10, height: 10)
                    VStack(alignment: .leading) {
                        Text(model.displayName(id)).lineLimit(1)
                        if model.tree.virtualKind(id) == nil {
                            Text(model.tree.path(id)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
                .overlay { DragOutHandle(model: model, id: id) }
                .help("Drag out of the Collector to remove it")
                Spacer()
                Text(ByteFormat.string(model.tree.size(id))).monospacedDigit().foregroundStyle(.secondary)
                Button { model.collector.remove(id) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove from Collector")
            }
            .contentShape(Rectangle())
            .onHover { if $0 { model.rowHovered = id } }
            .onTapGesture(count: 2) { if model.tree.virtualKind(id) == nil { QuickLookController.shared.toggle(path: model.tree.path(id)) } }
        }
        .onKeyPress(.space) {
            if let id = model.rowHovered, model.collector.contains(id), model.tree.virtualKind(id) == nil {
                QuickLookController.shared.toggle(path: model.tree.path(id))
            }
            return .handled
        }
        .frame(width: 420, height: min(360, CGFloat(model.collector.items.count) * 44 + 20))
    }
}

extension ResultsModel {
    /// Internal drags carry `majesdisk-node://<id>`; Finder drags carry file URLs inside the scanned tree.
    func node(forDropped url: URL) -> NodeID? {
        if url.scheme == "majesdisk-node", let id = url.host.flatMap(NodeID.init), id >= 0, Int(id) < tree.nodeCount { return id }
        return url.isFileURL ? tree.node(atPath: url.path) : nil
    }

    static func dragURL(for id: NodeID) -> URL { URL(string: "majesdisk-node://\(id)")! }
}
