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
            Picker("Show", selection: Binding(get: { model.sidebarMode }, set: { model.sidebarMode = $0; model.selected = nil })) {
                ForEach(SidebarMode.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding([.horizontal, .top], 12)
            SidebarHeader(model: model, folder: folder).padding(12)
            Divider()
            ScrollViewReader { proxy in
                List(selection: Binding(get: { model.selection }, set: { model.sidebarSelectionChanged($0, commandKey: NSEvent.modifierFlags.contains(.command)) })) {
                    ForEach(items, id: \.self) { id in
                        Group {
                            if model.sidebarMode == .suggestions, let s = model.suggestions.first(where: { $0.node == id }) {
                                SuggestionRow(model: model, suggestion: s)
                            } else {
                                SidebarRow(model: model, id: id, parentSize: tree.size(folder),
                                           location: model.sidebarMode == .largest ? model.location(of: id) : nil)
                            }
                        }
                        .id(id)
                        .listRowBackground(rowBackground(id))
                    }
                    if let fold = model.sidebarFold {
                        SmallerObjectsRow(model: model, folder: folder, start: fold)
                    }
                }
                .listStyle(.plain)
                .overlay {
                    if items.isEmpty && model.sidebarMode != .contents {
                        Text(model.sidebarMode == .largest ? "No files match these filters." : "Nothing obvious to clear here. Try Largest to find big files.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(24)
                    }
                }
                .contextMenu(forSelectionType: NodeID.self) { ids in
                    if ids.count > 1 {
                        Button("Move \(ids.count) Items to Collector") { model.tree.sortedByOrder(Array(ids)).forEach(model.addToCollector) }
                        Button("Reveal in Finder") { ids.forEach(model.reveal) }
                    } else if let id = ids.first { NodeContextMenu(model: model, id: id) }
                } primaryAction: { ids in
                    // Double-click or Return: open a folder, preview a file.
                    guard let id = ids.first else { return }
                    if model.isContainer(id) { model.enter(id) } else { QuickLookController.shared.toggle(path: tree.path(id)) }
                }
                .onKeyPress(.space) { QuickLookController.shared.toggle(model: model); return .handled }
                .onChange(of: model.selected) { _, sel in if let sel { proxy.scrollTo(sel) } }
            }
            Divider()
            if model.selection.count > 1, model.hovered == nil {
                let total = model.selection.reduce(UInt64(0)) { $0 + tree.size($1) }
                Text("^[\(model.selection.count) item](inflect: true) selected · \(ByteFormat.string(total))")
                    .font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(12)
            } else {
                ItemInfoView(model: model, id: model.pointed ?? folder)
            }
        }
    }

    func rowBackground(_ id: NodeID) -> Color {
        if id == model.hovered || id == model.rowHovered { return Color.accentColor.opacity(0.15) }
        return .clear
    }
}

/// Title and summary above the list; in Largest mode, the filters.
struct SidebarHeader: View {
    let model: ResultsModel
    let folder: NodeID

    var body: some View {
        let tree = model.tree
        VStack(alignment: .leading, spacing: 6) {
            switch model.sidebarMode {
            case .contents:
                Text(model.expandedSmallerObjects?.parent == folder ? "Smaller objects in \(model.displayName(folder))" : model.displayName(folder))
                    .font(.headline).lineLimit(1).truncationMode(.middle)
                HStack {
                    Text("\(ByteFormat.string(tree.size(folder))) · ^[\(tree.itemCount(folder)) item](inflect: true)")
                        .font(.caption).foregroundStyle(.secondary)
                    if let d = model.delta(folder), abs(d) >= 1_000_000 { GrowthBadge(delta: d) }
                    Spacer()
                    if model.previous != nil {
                        Picker("Sort", selection: Binding(get: { model.sortByGrowth }, set: { model.sortByGrowth = $0 })) {
                            Text("By size").tag(false)
                            Text("By growth").tag(true)
                        }
                        .labelsHidden().controlSize(.small).fixedSize()
                        .help("Compare with the previous scan of this folder")
                    }
                }
            case .largest:
                Text("Biggest files in \(model.displayName(folder))").font(.headline).lineLimit(1).truncationMode(.middle)
                HStack {
                    Picker("Kind", selection: Binding(get: { model.largestKind }, set: { model.largestKind = $0 })) {
                        Text("All kinds").tag(FileKind?.none)
                        Text("Videos").tag(FileKind?.some(.video))
                        Text("Archives & disk images").tag(FileKind?.some(.archives))
                        Text("Apps").tag(FileKind?.some(.apps))
                        Text("Everything else").tag(FileKind?.some(.other))
                    }
                    Picker("Age", selection: Binding(get: { model.largestOlderThanMonths }, set: { model.largestOlderThanMonths = $0 })) {
                        Text("Any age").tag(Int?.none)
                        Text("Unchanged 6+ months").tag(Int?.some(6))
                        Text("Unchanged 1+ year").tag(Int?.some(12))
                    }
                }
                .labelsHidden().controlSize(.small)
            case .suggestions:
                Text("Usually safe to clear").font(.headline)
                Text("Folders apps and tools rebuild on their own. Read the note before collecting.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A cleanup suggestion: what it is, why it's (usually) safe, and a one-click Collect.
struct SuggestionRow: View {
    let model: ResultsModel
    let suggestion: CleanupSuggestion

    var body: some View {
        let id = suggestion.node
        HStack(alignment: .top, spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: model.tree.path(id))).resizable().frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title).fontWeight(.medium)
                Text(LocalizedStringKey(suggestion.note)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                Text(ByteFormat.string(model.tree.size(id))).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Button(model.isCollected(id) ? "Collected" : "Collect") { model.addToCollector(id) }
                    .controlSize(.small).disabled(model.isCollected(id))
            }
        }
        .padding(.vertical, 2)
        .onDrag { NSItemProvider(object: ResultsModel.dragURL(for: id, in: model) as NSURL) }
    }
}

struct SidebarRow: View {
    let model: ResultsModel
    let id: NodeID
    let parentSize: UInt64
    /// Where the file lives, shown in Largest mode (files come from many folders).
    var location: String? = nil

    var body: some View {
        let tree = model.tree
        let flags = tree.flags(id)
        HStack(spacing: 8) {
            Circle().fill(Color(nsColor: model.color(for: id).nsColor)).frame(width: 8, height: 8)
            if tree.virtualKind(id) == nil {
                Image(nsImage: NSWorkspace.shared.icon(forFile: tree.path(id))).resizable().frame(width: 18, height: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(model.displayName(id)).lineLimit(1).truncationMode(.middle)
                        .strikethrough(flags.contains(.deleted) || flags.contains(.vanished))
                        .foregroundStyle(flags.contains(.vanished) ? .secondary : .primary)
                        .help(flags.contains(.vanished) ? "Removed outside MajesDisk since the scan" : "")
                    if flags.contains(.changed) {
                        Text("changed").font(.caption2).foregroundStyle(.orange)
                            .help("Changed outside MajesDisk since the scan; sizes may be out of date")
                    }
                    if flags.contains(.secondaryLink) { Text("hard link").font(.caption2).foregroundStyle(.secondary) }
                    if flags.contains(.restricted) { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.purple) }
                }
                if let d = model.delta(id), abs(d) >= 1_000_000 { GrowthBadge(delta: d) }
                if let location {
                    Text(location).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                }
                GeometryReader { g in
                    Capsule().fill(Color.secondary.opacity(0.35))
                        .frame(width: g.size.width * (parentSize > 0 ? Double(tree.size(id)) / Double(parentSize) : 0))
                }
                .frame(height: 3)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(ByteFormat.string(tree.size(id))).font(.callout.monospacedDigit())
                if parentSize > 0 {
                    Text(Double(tree.size(id)) / Double(parentSize), format: .percent.precision(.fractionLength(0...1)))
                        .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { model.rowHovered = id } else if model.rowHovered == id { model.rowHovered = nil }
        }
        .onDrag { NSItemProvider(object: ResultsModel.dragURL(for: id, in: model) as NSURL) }
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

/// "+52 MB" since the previous scan: orange when something grew, green when space was freed.
struct GrowthBadge: View {
    let delta: Int64

    var body: some View {
        Text((delta > 0 ? "+" : "−") + ByteFormat.string(UInt64(abs(delta))))
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(delta > 0 ? Color.orange : Color.green)
            .help(delta > 0 ? "Grew since the previous scan" : "Smaller than in the previous scan")
    }
}
