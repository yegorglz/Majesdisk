import AppKit
import MajesCore
import SwiftUI

/// Contents of the pointed folder, largest first, with the pointed item's details below.
struct SidebarView: View {
    let model: ResultsModel

    var body: some View {
        let folder = model.sidebarFolder
        let items = model.sidebarItems
        let tree = model.tree
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.expandedSmallerObjects?.parent == folder ? "Smaller objects in \(model.displayName(folder))" : model.displayName(folder))
                    .font(.headline).lineLimit(1).truncationMode(.middle)
                Text("\(ByteFormat.string(tree.size(folder))) · \(tree.itemCount(folder).formatted()) items")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()
            ScrollViewReader { proxy in
                List(selection: Binding(get: { model.selected }, set: { model.sidebarSelectionChanged($0, commandKey: NSEvent.modifierFlags.contains(.command)) })) {
                    ForEach(items, id: \.self) { id in
                        SidebarRow(model: model, id: id, parentSize: tree.size(folder))
                            .id(id)
                            .listRowBackground(rowBackground(id))
                    }
                    if let fold = model.sidebarFold {
                        SmallerObjectsRow(model: model, folder: folder, start: fold)
                    }
                }
                .listStyle(.plain)
                .contextMenu(forSelectionType: NodeID.self) { ids in
                    if let id = ids.first { NodeContextMenu(model: model, id: id) }
                } primaryAction: { ids in
                    // Double-click or Return: open a folder, preview a file.
                    guard let id = ids.first else { return }
                    if model.isContainer(id) { model.enter(id) } else { QuickLookController.shared.toggle(path: tree.path(id)) }
                }
                .onKeyPress(.space) { QuickLookController.shared.toggle(model: model); return .handled }
                .onChange(of: model.selected) { _, sel in if let sel { proxy.scrollTo(sel) } }
            }
            Divider()
            ItemInfoView(model: model, id: model.pointed ?? folder)
        }
    }

    func rowBackground(_ id: NodeID) -> Color {
        if id == model.hovered || id == model.rowHovered { return Color.accentColor.opacity(0.15) }
        return .clear
    }
}

struct SidebarRow: View {
    let model: ResultsModel
    let id: NodeID
    let parentSize: UInt64

    var body: some View {
        let tree = model.tree
        let flags = tree.flags(id)
        HStack(spacing: 8) {
            Circle().fill(Color(nsColor: model.color(for: id).nsColor)).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(model.displayName(id)).lineLimit(1).truncationMode(.middle)
                        .strikethrough(flags.contains(.deleted))
                    if flags.contains(.secondaryLink) { Text("hard link").font(.caption2).foregroundStyle(.secondary) }
                    if flags.contains(.restricted) { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.purple) }
                }
                GeometryReader { g in
                    Capsule().fill(Color.secondary.opacity(0.35))
                        .frame(width: g.size.width * (parentSize > 0 ? Double(tree.size(id)) / Double(parentSize) : 0))
                }
                .frame(height: 3)
            }
            Spacer(minLength: 4)
            Text(ByteFormat.string(tree.size(id))).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { model.rowHovered = id } else if model.rowHovered == id { model.rowHovered = nil }
        }
        .onDrag { NSItemProvider(object: ResultsModel.dragURL(for: id) as NSURL) }
    }
}

/// The folded tail of a folder's list; clicking opens the full list, as in the map.
struct SmallerObjectsRow: View {
    let model: ResultsModel
    let folder: NodeID
    let start: Int

    var body: some View {
        let tail = model.tree.children(folder).dropFirst(start)
        Button { model.expandSmallerObjects(SmallerObjectsRef(parent: folder, start: start)) } label: {
            HStack(spacing: 8) {
                Circle().fill(Color(nsColor: model.color(for: folder).nsColor).opacity(0.35)).frame(width: 10, height: 10)
                Text("\(tail.count.formatted()) smaller objects").foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(ByteFormat.string(tail.reduce(0) { $0 + model.tree.size($1) })).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ItemInfoView: View {
    let model: ResultsModel
    let id: NodeID

    var body: some View {
        let tree = model.tree
        VStack(alignment: .leading, spacing: 4) {
            Text(model.displayName(id)).font(.headline).lineLimit(2)
            if tree.virtualKind(id) == nil {
                Text(tree.path(id)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(3)
            }
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
                GridRow { Text("Kind").foregroundStyle(.secondary); Text(kind) }
                GridRow { Text("Size").foregroundStyle(.secondary); Text(ByteFormat.string(tree.size(id))) }
                if model.isContainer(id) || tree.flags(id).contains(.package) {
                    GridRow { Text("Items").foregroundStyle(.secondary); Text(tree.itemCount(id).formatted()) }
                }
                if let date = modified {
                    GridRow { Text("Modified").foregroundStyle(.secondary); Text(date.formatted(date: .abbreviated, time: .shortened)) }
                }
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    var kind: String {
        let f = model.tree.flags(id)
        if f.contains(.virtual) { return "Virtual item" }
        if f.contains(.restricted) { return "Restricted folder" }
        if f.contains(.package) { return "Package" }
        if f.contains(.directory) { return "Folder" }
        if f.contains(.symlink) { return "Symbolic link" }
        return f.contains(.secondaryLink) ? "File (hard link or clone, counted once)" : "File"
    }

    var modified: Date? {
        guard model.tree.virtualKind(id) == nil else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: model.tree.path(id)))?[.modificationDate] as? Date
    }
}
