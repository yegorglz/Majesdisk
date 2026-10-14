import AppKit
import MajesCore
import Observation

struct AlertInfo: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    /// Paths that failed for lack of permission; the alert offers to delete them as administrator.
    var adminRetryPaths: [String] = []
}

/// Runs the Collector's Delete: a 5-second cancelable countdown, then deletion off the main thread.
@MainActor @Observable
final class DeletionController {
    enum Phase: Equatable { case idle, countdown(remaining: Int), deleting }
    var phase: Phase = .idle
    /// When the countdown ends; drives the draining ring.
    var deadline = Date()
    @ObservationIgnored private var task: Task<Void, Never>?

    func begin(model: ResultsModel) {
        guard phase == .idle, !model.collector.items.isEmpty else { return }
        deadline = Date().addingTimeInterval(5)
        task = Task { [weak self] in
            for remaining in stride(from: 5, through: 1, by: -1) {
                self?.phase = .countdown(remaining: remaining)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { self?.phase = .idle; return }
            }
            self?.phase = .deleting
            await model.deleteCollected()
            self?.phase = .idle
            model.compactIfNeeded()
        }
    }

    func cancel() {
        guard case .countdown = phase else { return }
        task?.cancel()
        phase = .idle
    }
}

extension ResultsModel {
    var deleteMode: DeleteMode { DeleteMode(rawValue: UserDefaults.standard.string(forKey: "deleteMode") ?? "") ?? .permanent }

    func protectionVerdict(_ path: String) -> ProtectionVerdict {
        ProtectedPaths.verdict(for: path, volumeRoots: AppModel.shared.volumes.map(\.mountPath))
    }

    func toggleCollector(_ id: NodeID) {
        if collector.contains(id) { collector.remove(id) } else { addToCollector(id) }
    }

    func addToCollector(_ id: NodeID) {
        switch collector.add(id, in: tree, verdict: protectionVerdict) {
        case .rejected(let why):
            alert = AlertInfo(title: "“\(displayName(id))” can't be collected", message: why)
        case .alreadyCovered:
            if let holder = collector.items.first(where: { tree.isAncestor($0, of: id) }) {
                alert = AlertInfo(title: "Already in the Collector", message: "It's inside “\(displayName(holder))”, which is collected.")
            }
        case .added: break
        }
    }

    /// Deletes everything in the Collector and updates the map in place.
    func deleteCollected() async {
        let ids = collector.items
        if let purgeable = ids.first(where: { tree.virtualKind($0) == .purgeable }) {
            collector.remove(purgeable)
            PurgeAction.run(model: self, node: purgeable)
        }
        let files = ids.filter { tree.virtualKind($0) == nil }
        guard !files.isEmpty else { return }
        let paths = files.map(tree.path)
        let mode = deleteMode
        let volumeRoots = AppModel.shared.volumes.map(\.mountPath)
        let outcomes = await Task.detached(priority: .userInitiated) {
            Deleter.delete(paths: paths, mode: mode) { ProtectedPaths.verdict(for: $0, volumeRoots: volumeRoots) }
        }.value
        applyDeletions(outcomes, ids: Dictionary(uniqueKeysWithValues: zip(paths, files)))
    }

    func applyDeletions(_ outcomes: [DeleteOutcome], ids: [String: NodeID]) {
        var failures: [DeleteOutcome] = []
        for o in outcomes {
            guard let id = ids[o.path] else { continue }
            if o.failure == nil || o.failure == .notFound {
                ownDeletions.insert(o.path)
                tree.markDeleted(id)
                collector.remove(id)
            }
            if let f = o.failure, f != .notFound { failures.append(o) }
        }
        leaveGoneCenter()
        isDirty = true
        treeVersion += 1
        AppModel.shared.refreshVolumes()
        guard !failures.isEmpty else { compactIfNeeded(); return }  // with failures, the rescan below compacts when done
        let lines = failures.map { o -> String in
            let why: String
            switch o.failure {
            case .protected(let s): why = s
            case .permissionDenied: why = "permission denied"
            case .other(let s): why = s
            default: why = "unknown error"
            }
            return "\((o.path as NSString).lastPathComponent): \(why)"
        }
        // A folder delete stops at the first file it can't remove, so part of it may be gone: re-measure it.
        rescan(failures.compactMap { o in
            guard case .protected = o.failure else { return ids[o.path].flatMap { tree.flags($0).contains(.directory) ? $0 : nil } }
            return nil
        })
        let denied = failures.filter { $0.failure == .permissionDenied }.map(\.path)
        alert = AlertInfo(title: "Some items couldn't be deleted", message: lines.joined(separator: "\n"), adminRetryPaths: denied)
    }
}
