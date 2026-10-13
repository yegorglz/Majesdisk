import MajesCore

// Filled in by Tasks 12, 14 and 18.
@MainActor final class QuickLookController {
    static let shared = QuickLookController()
    func toggle(model: ResultsModel) {}
}

extension ResultsModel {
    func toggleCollector(_ id: NodeID) {}
    func rescanFolder(_ id: NodeID) {}
    func rescanAll() {}
}

/// Placeholder until Task 14.
struct CollectorPlaceholder { var items: [NodeID] = []; func contains(_ id: NodeID) -> Bool { false } }
extension ResultsModel { var collector: CollectorPlaceholder { CollectorPlaceholder() } }
