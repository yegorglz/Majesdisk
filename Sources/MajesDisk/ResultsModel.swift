import AppKit
import MajesCore
import MajesMap
import Observation

/// A folder's tail of tiny children merged into one "smaller objects" wedge.
struct SmallerObjectsRef: Equatable { var parent: NodeID; var start: Int }

/// What the sidebar lists: the pointed folder's contents, the biggest files under the map center,
/// or cleanup suggestions.
enum SidebarMode: String, CaseIterable { case contents = "Contents", largest = "Largest", suggestions = "Suggestions" }

@MainActor @Observable
final class ResultsModel {
    let tree: FileTree
    let volume: VolumeInfo?
    let asAdministrator: Bool
    var history: NavigationHistory
    var hovered: NodeID?
    var hoveredSmallerObjects: SmallerObjectsRef?
    /// Set when the user opens a "smaller objects" wedge: the sidebar lists all of them.
    var expandedSmallerObjects: SmallerObjectsRef?
    /// Rows picked in the sidebar (shift-click ranges); `selected` is the one the keyboard and map follow.
    var selection: Set<NodeID> = []
    private var primarySelection: NodeID?
    var selected: NodeID? {
        get { primarySelection }
        set { primarySelection = newValue; selection = newValue.map { [$0] } ?? [] }
    }
    var expandedPackages: Set<NodeID> = []
    var treeVersion = 0
    var transition: TransitionDirection = .zoomIn
    /// Row under the mouse in the sidebar: highlights its wedge without changing the sidebar folder.
    var rowHovered: NodeID?
    var collector = Collector()
    let deletion = DeletionController()
    var alert: AlertInfo?
    var isRescanning = false
    var sidebarMode: SidebarMode = .contents
    var largestKind: FileKind?
    var largestOlderThanMonths: Int?
    @ObservationIgnored private var largestCache: (key: [Int], items: [NodeID])?
    /// Folders changed outside the app since the scan (outermost first come from `staleFolders`).
    var changedFolders: Set<NodeID> = []
    @ObservationIgnored private var watcher: FolderWatcher?
    /// Paths this app deleted: their file-system events aren't outside changes.
    @ObservationIgnored var ownDeletions: Set<String> = []
    @ObservationIgnored private var suggestionsCache: (version: Int, items: [CleanupSuggestion])?

    /// Known regenerable space hogs in this scan (whole scan, not just the map center).
    var suggestions: [CleanupSuggestion] {
        if let c = suggestionsCache, c.version == treeVersion { return c.items }
        let items = CleanupSuggestions.find(in: tree, extraHomes: [NSHomeDirectory()]).filter { !tree.isGone($0.node) }
        suggestionsCache = (treeVersion, items)
        return items
    }
    @ObservationIgnored private var layoutCache: (key: [Int], segments: [SunburstSegment])?

    /// The previous saved scan of the same folder, if any, for "what grew" (shortcut: held in memory
    /// alongside the current tree, doubling its RAM; drop it if memory becomes a problem).
    let previous: FileTree?
    let scannedAt: Date
    /// Edited (deleted or rescanned) since it was saved; re-saved on quit.
    var isDirty = false
    var sortByGrowth = false

    init(tree: FileTree, volume: VolumeInfo?, asAdministrator: Bool, previous: FileTree? = nil, scannedAt: Date = Date()) {
        self.tree = tree; self.volume = volume; self.asAdministrator = asAdministrator
        self.previous = previous; self.scannedAt = scannedAt
        history = NavigationHistory(start: tree.root)
    }

    var center: NodeID { history.current }

    /// The item the user is pointing at, by mouse or keyboard.
    var pointed: NodeID? { hovered ?? selected ?? rowHovered }
    /// Folder the sidebar stays on after the user picks one of its rows (instead of snapping back to the center).
    var sidebarAnchor: NodeID?

    /// Map wedges for the current center, recomputed only when the center, tree or package expansion changes.
    var segments: [SunburstSegment] {
        let key = [Int(center), treeVersion] + expandedPackages.map(Int.init).sorted()
        if let c = layoutCache, c.key == key { return c.segments }
        let segs = SunburstLayout.layout(tree: tree, center: center, expandedPackages: expandedPackages)
        layoutCache = (key, segs)
        return segs
    }

    /// The color a node's dot uses in lists: its wedge's color when drawn, otherwise its kind's.
    func color(for id: NodeID) -> RGBA {
        if let s = segments.first(where: { $0.node == id && $0.kind != .smallerObjects }) {
            return SunburstPalette.color(for: s, highlighted: false)
        }
        let kind = SunburstLayout.kind(of: id, in: tree)
        let angle = segments.first(where: { $0.node == tree.parent(id) })?.midAngle ?? 0
        return SunburstPalette.color(for: SunburstSegment(node: id, aggregateStartIndex: nil, kind: kind, depth: 1, startAngle: angle, endAngle: angle), highlighted: false)
    }

    func displayName(_ id: NodeID) -> String {
        id == tree.root ? (volume?.name ?? (tree.rootPath == "/" ? "/" : (tree.rootPath as NSString).lastPathComponent)) : tree.name(id)
    }

    func isContainer(_ id: NodeID) -> Bool {
        let f = tree.flags(id)
        if f.contains(.package) { return expandedPackages.contains(id) }
        return f.contains(.directory) || f.contains(.virtual)
    }

    /// The sidebar follows the pointed folder (or a pointed file's folder), else the map center.
    var sidebarFolder: NodeID {
        if sidebarMode != .contents { return center }
        if let s = hoveredSmallerObjects { return s.parent }
        if let h = hovered { return isContainer(h) && !tree.children(h).isEmpty ? h : (tree.parent(h) ?? center) }
        return sidebarAnchor ?? center
    }

    /// The 200 biggest files under the map center, optionally of one kind and untouched for N months.
    var largestItems: [NodeID] {
        let key = [Int(center), treeVersion, FileKind.allCases.firstIndex { $0 == largestKind } ?? -1, largestOlderThanMonths ?? 0]
        if let c = largestCache, c.key == key { return c.items }
        var items: [NodeID]
        if let months = largestOlderThanMonths {
            // Dates aren't kept in the tree: check them only for the top candidates.
            let cutoff = Date().addingTimeInterval(-Double(months) * 30.4 * 86_400)
            items = tree.largestFiles(under: center, limit: 2_000, kind: largestKind).filter { id in
                var st = stat()
                guard lstat(tree.path(id), &st) == 0 else { return false }
                return Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec)) < cutoff
            }
            items = Array(items.prefix(200))
        } else {
            items = tree.largestFiles(under: center, limit: 200, kind: largestKind)
        }
        largestCache = (key, items)
        return items
    }

    /// Bytes gained (positive) or freed since the previous scan; nil without one. New items count fully.
    func delta(_ id: NodeID) -> Int64? {
        guard let previous, tree.virtualKind(id) == nil else { return nil }
        let before = previous.node(atPath: tree.path(id)).map { previous.size($0) } ?? 0
        return Int64(tree.size(id)) - Int64(before)
    }

    /// A node's folder relative to the map center, for rows listed out of their folder.
    func location(of id: NodeID) -> String {
        guard let parent = tree.parent(id) else { return "" }
        let base = tree.path(center), full = tree.path(parent)
        return full == base ? displayName(center) : String(full.dropFirst(base.hasSuffix("/") ? base.count : base.count + 1))
    }

    /// In the Collector itself or inside a collected folder: Delete will remove it.
    func isCollected(_ id: NodeID) -> Bool {
        let held = Set(collector.items)
        var cur: NodeID? = id
        while let c = cur { if held.contains(c) { return true }; cur = tree.parent(c) }
        return false
    }

    /// A row picked in the sidebar: keep that list on screen and let the keyboard drive from there.
    func selectFromSidebar(_ id: NodeID?) {
        guard id != selected else { return }
        if id != nil, hovered != nil || hoveredSmallerObjects != nil {
            sidebarAnchor = sidebarFolder
            hovered = nil; hoveredSmallerObjects = nil
        }
        selected = id
    }

    var sidebarItems: [NodeID] {
        switch sidebarMode {
        case .largest: return largestItems
        case .suggestions: return suggestions.map(\.node)
        case .contents: break
        }
        let all = tree.children(sidebarFolder)
        if sortByGrowth, previous != nil { return all.sorted { (delta($0) ?? 0) > (delta($1) ?? 0) } }
        if let s = expandedSmallerObjects, s.parent == sidebarFolder, s.start < all.count { return Array(all[s.start...]) }
        return Array(all.prefix(sidebarFold ?? all.count))
    }

    /// Where the sidebar folds the tail into one "N smaller objects" row: the map's 0.6° rule,
    /// measured as if the folder were the center. Nil when nothing (or only one item) would fold.
    var sidebarFold: Int? {
        let folder = sidebarFolder
        guard sidebarMode == .contents, !(sortByGrowth && previous != nil), expandedSmallerObjects?.parent != folder, tree.size(folder) > 0 else { return nil }
        let all = tree.children(folder)
        let total = Double(tree.size(folder))
        guard let i = all.firstIndex(where: { 2 * .pi * Double(tree.size($0)) / total < SunburstConfig().minSegmentAngle }),
              all.count - i > 1 else { return nil }
        return i
    }

    // MARK: Navigation

    func enter(_ id: NodeID) {
        guard isContainer(id), id != center else { return }
        transition = .zoomIn
        history.visit(id)
        resetPointer()
    }

    func goUp() {
        guard let p = tree.parent(center) else { return }
        transition = .zoomOut
        history.visit(p)
        resetPointer()
    }

    func goBack() { step { $0.goBack() } }
    func goForward() { step { $0.goForward() } }

    /// Moves through history, skipping folders deleted since they were visited.
    private func step(_ move: (inout NavigationHistory) -> NodeID?) {
        let before = center
        while let n = move(&history), tree.isGone(n) {}
        if tree.isGone(center) { history.visit(tree.root) }  // ran out of live entries
        guard center != before else { return }
        transition = tree.isAncestor(center, of: before) ? .zoomOut : .zoomIn
        resetPointer()
    }

    // MARK: Changes made outside the app

    func startWatching(since: FSEventStreamEventId) {
        // realpath, not resolvingSymlinksInPath: the latter strips /private, FSEvents doesn't.
        let realRoot = realpath(tree.rootPath, nil).map { p in defer { free(p) }; return String(cString: p) } ?? tree.rootPath
        let root = tree.rootPath
        watcher = FolderWatcher(path: root, since: since) { [weak self] paths in
            // Events use the real path (/private/tmp); the tree may use the link (/tmp).
            self?.handleChanges(paths.map { $0.hasPrefix(realRoot) && realRoot != root ? root + $0.dropFirst(realRoot.count) : $0 })
        }
    }

    func stopWatching() { watcher?.stop(); watcher = nil }

    /// Removed items get struck out; their folder (or the nearest scanned folder of a new item) is marked changed.
    func handleChanges(_ paths: [String]) {
        var touched = false
        for p in Set(paths.map { $0.hasSuffix("/") && $0.count > 1 ? String($0.dropLast()) : $0 }) {
            if ownDeletions.contains(where: { p == $0 || p.hasPrefix($0 + "/") }) { continue }
            var st = stat()
            let exists = lstat(p, &st) == 0
            if let id = tree.node(atPath: p) {
                if !exists, id != tree.root {
                    tree.insertFlags(.vanished, into: id)
                    if let parent = tree.parent(id) { markChanged(parent) }
                } else if tree.flags(id).contains(.directory) {
                    markChanged(id)
                } else if let parent = tree.parent(id) {
                    markChanged(parent)
                }
            } else {
                var folder = (p as NSString).deletingLastPathComponent
                while tree.node(atPath: folder) == nil, folder.count > tree.rootPath.count { folder = (folder as NSString).deletingLastPathComponent }
                if let id = tree.node(atPath: folder) { markChanged(id) }
            }
            touched = true
        }
        if touched { treeVersion += 1 }
    }

    private func markChanged(_ id: NodeID) {
        tree.insertFlags(.changed, into: id)
        changedFolders.insert(id)
    }

    /// Changed folders worth rescanning: still present, and not inside another changed folder.
    var staleFolders: [NodeID] {
        let live = changedFolders.filter { !tree.isGone($0) }
        return tree.sortedByOrder(live.filter { id in !live.contains { $0 != id && tree.isAncestor($0, of: id) } })
    }

    /// Frees nodes left behind by deletes and rescans once they outnumber the live ones.
    func compactIfNeeded() {
        // A running rescan or delete holds node IDs; each compacts when it finishes.
        guard !isRescanning, deletion.phase != .deleting, tree.garbageCount > tree.nodeCount - tree.garbageCount else { return }
        let map = tree.compact()
        history = NavigationHistory(start: map[center] ?? tree.root)
        collector.remap(map)
        changedFolders = Set(changedFolders.compactMap { map[$0] })
        expandedPackages = Set(expandedPackages.compactMap { map[$0] })
        hovered = nil; rowHovered = nil; selected = nil; hoveredSmallerObjects = nil; expandedSmallerObjects = nil; sidebarAnchor = nil
        treeVersion += 1
    }

    /// After deletes or rescans, the map's center may no longer exist: move up to the nearest live folder.
    func leaveGoneCenter() {
        var live = center
        while tree.isGone(live), let p = tree.parent(live) { live = p }
        if live != center { history.visit(live) }
    }

    func navigate(to id: NodeID) {
        let before = center
        guard id != before else { return }
        transition = tree.isAncestor(id, of: before) ? .zoomOut : .zoomIn
        history.visit(id)
        resetPointer()
    }

    func expandSmallerObjects(_ ref: SmallerObjectsRef) {
        expandedSmallerObjects = ref
        if ref.parent != center { navigate(to: ref.parent); expandedSmallerObjects = ref }
    }

    private func resetPointer() {
        hovered = nil; hoveredSmallerObjects = nil; expandedSmallerObjects = nil; selected = nil; rowHovered = nil; sidebarAnchor = nil
    }

    func togglePackage(_ id: NodeID) {
        if expandedPackages.contains(id) { expandedPackages.remove(id) } else { expandedPackages.insert(id) }
        treeVersion += 1
    }

    // MARK: Keyboard

    func perform(_ action: BrowserAction) {
        switch action {
        case .selectPrevious: moveSelection { $0 - 1 }
        case .selectNext: moveSelection { $0 + 1 }
        case .pageUp: moveSelection { $0 - 10 }
        case .pageDown: moveSelection { $0 + 10 }
        case .selectFirst: moveSelection { _ in 0 }
        case .selectLast: moveSelection { _ in Int.max }
        case .goUp: goUp()
        case .goBack: goBack()
        case .goForward: goForward()
        case .enter:
            if let s = hoveredSmallerObjects { expandSmallerObjects(s) } else if let p = pointed { enter(p) }
        case .quickLook: QuickLookController.shared.toggle(model: self)
        case .toggleCollector where selection.count > 1 && hovered == nil && hoveredSmallerObjects == nil:
            // Several rows picked: collect them all, or release them all if they're all collected already.
            if selection.allSatisfy(collector.contains) { selection.forEach { collector.remove($0) } }
            else { tree.sortedByOrder(Array(selection)).forEach(addToCollector) }
        case .toggleCollector:
            if hoveredSmallerObjects != nil {
                alert = AlertInfo(title: "Smaller objects can't be collected",
                                  message: "Open the group (click it or press Return) and collect its files individually.")
            } else if let p = pointed { toggleCollector(p) }
        case .rescanFolder:
            rescanFolder(hoveredSmallerObjects?.parent ?? pointed.flatMap { isContainer($0) ? $0 : nil } ?? center)
        case .rescanAll: rescanAll()
        }
    }

    private func moveSelection(_ step: (Int) -> Int) {
        hovered = nil; hoveredSmallerObjects = nil
        let items = sidebarItems
        guard !items.isEmpty else { return }
        let current = selected.flatMap { items.firstIndex(of: $0) } ?? -1
        let target = current < 0 ? (step(0) == Int.max ? items.count - 1 : 0) : step(current)
        selected = items[min(items.count - 1, max(0, target))]
    }

    static let defaultReveal: (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    /// Swapped in tests so they don't open Finder windows.
    static var revealInFinder = defaultReveal

    func reveal(_ id: NodeID) {
        guard !tree.flags(id).contains(.virtual) else { return }
        Self.revealInFinder(URL(fileURLWithPath: tree.path(id)))
    }

    /// The sidebar list's selection setter. ⌘-click reveals the clicked row in Finder instead of
    /// changing the selection (DaisyDisk's ⌘-click); shift-click ranges select several rows.
    func sidebarSelectionChanged(_ ids: Set<NodeID>, commandKey: Bool) {
        if commandKey {
            if let target = ids.symmetricDifference(selection).first ?? selected { reveal(target) }
            return
        }
        let added = ids.subtracting(selection)
        let primary = added.first ?? (selected.map { ids.contains($0) } == true ? selected : ids.first)
        selectFromSidebar(primary)
        selection = ids
    }
}
