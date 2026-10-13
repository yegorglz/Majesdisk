import AppKit
import MajesCore
import MajesMap
import Observation

/// A folder's tail of tiny children merged into one "smaller objects" wedge.
struct SmallerObjectsRef: Equatable { var parent: NodeID; var start: Int }

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
    var selected: NodeID?
    var expandedPackages: Set<NodeID> = []
    var treeVersion = 0
    var transition: TransitionDirection = .zoomIn

    init(tree: FileTree, volume: VolumeInfo?, asAdministrator: Bool) {
        self.tree = tree; self.volume = volume; self.asAdministrator = asAdministrator
        history = NavigationHistory(start: tree.root)
    }

    var center: NodeID { history.current }

    /// The item the user is pointing at, by mouse or keyboard.
    var pointed: NodeID? { hovered ?? selected }

    func isContainer(_ id: NodeID) -> Bool {
        let f = tree.flags(id)
        if f.contains(.package) { return expandedPackages.contains(id) }
        return f.contains(.directory) || f.contains(.virtual)
    }

    /// The sidebar follows the pointed folder (or a pointed file's folder), else the map center.
    var sidebarFolder: NodeID {
        if let s = hoveredSmallerObjects { return s.parent }
        if let h = hovered { return isContainer(h) && !tree.children(h).isEmpty ? h : (tree.parent(h) ?? center) }
        return center
    }

    var sidebarItems: [NodeID] {
        let all = tree.children(sidebarFolder)
        if let s = expandedSmallerObjects, s.parent == sidebarFolder, s.start < all.count { return Array(all[s.start...]) }
        return all
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

    func goBack() {
        let before = center
        if let id = history.goBack() { transition = tree.isAncestor(id, of: before) ? .zoomOut : .zoomIn; resetPointer() }
    }

    func goForward() {
        let before = center
        if let id = history.goForward() { transition = tree.isAncestor(before, of: id) ? .zoomIn : .zoomOut; resetPointer() }
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
        hovered = nil; hoveredSmallerObjects = nil; expandedSmallerObjects = nil; selected = nil
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
        case .toggleCollector: if let p = pointed { toggleCollector(p) }
        case .rescanFolder: rescanFolder(pointed.flatMap { isContainer($0) ? $0 : nil } ?? center)
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

    func reveal(_ id: NodeID) {
        guard !tree.flags(id).contains(.virtual) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: tree.path(id))])
    }
}
