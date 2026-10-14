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
                CountdownRing(deadline: model.deletion.deadline, seconds: n)
                Text(model.deleteMode == .moveToTrash ? "Moving to Trash…" : "Deleting…").foregroundStyle(.secondary)
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
            let ids = urls.flatMap(model.nodes(forDropped:))
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
    /// Internal drags carry `majesdisk-node://<id>` (or `…://selection` for several rows);
    /// Finder drags carry file URLs inside the scanned tree.
    func nodes(forDropped url: URL) -> [NodeID] {
        if url.scheme == "majesdisk-node" {
            if url.host == "selection" { return tree.sortedByOrder(Array(selection)) }
            if let id = url.host.flatMap(NodeID.init), id >= 0, Int(id) < tree.nodeCount { return [id] }
            return []
        }
        return url.isFileURL ? tree.node(atPath: url.path).map { [$0] } ?? [] : []
    }

    static func dragURL(for id: NodeID) -> URL { URL(string: "majesdisk-node://\(id)")! }

    /// Dragging one row of a multi-selection drags the whole selection.
    static func dragURL(for id: NodeID, in model: ResultsModel) -> URL {
        model.selection.count > 1 && model.selection.contains(id) ? URL(string: "majesdisk-node://selection")! : dragURL(for: id)
    }
}

/// The 5-second fuse before a delete: a red ring that drains smoothly, seconds left in the middle.
struct CountdownRing: View {
    let deadline: Date
    let seconds: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let left = reduceMotion ? Double(seconds) : max(0, deadline.timeIntervalSince(context.date))
            ZStack {
                Circle().stroke(Color.red.opacity(0.2), lineWidth: 3)
                Circle().trim(from: 0, to: left / 5)
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(seconds)").font(.system(.caption, design: .rounded).weight(.bold)).monospacedDigit()
            }
        }
        .frame(width: 26, height: 26)
        .accessibilityLabel("Deleting in \(seconds) seconds")
    }
}
