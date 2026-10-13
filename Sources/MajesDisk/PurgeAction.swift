import Foundation
import MajesCore

/// Purgeable space dropped on the Collector: ask macOS to thin local snapshots, then follow the
/// recalculation (it lags by minutes) and resize the map's purgeable item in place.
enum PurgeAction {
    @MainActor static func run(model: ResultsModel, node: NodeID) {
        let mount = model.volume?.mountPath ?? "/"
        Task {
            do {
                _ = try await AdminRunner(prompt: "MajesDisk wants to free purgeable space.").run(Snapshots.purgeCommand(mountPath: mount))
            } catch AdminRunnerError.cancelled {
                return
            } catch {
                model.alert = AlertInfo(title: "Couldn't free purgeable space", message: "\(error)")
                return
            }
            for _ in 0..<12 {
                if let v = VolumeLister.info(for: URL(fileURLWithPath: mount)) {
                    model.tree.setVirtualSize(node, min(model.tree.size(node), v.purgeableBytes))
                    model.treeVersion += 1
                    AppModel.shared.refreshVolumes()
                }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }
}
