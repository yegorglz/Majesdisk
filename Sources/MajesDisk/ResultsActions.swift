import MajesCore

// Filled in by Task 18.
extension ResultsModel {
    func rescanFolder(_ id: NodeID) {}
    func rescanAll() {}
}

/// Filled in by Task 17.
enum PurgeAction { @MainActor static func run(model: ResultsModel, node: NodeID) {} }
