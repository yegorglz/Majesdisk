import MajesCore
import Observation

@MainActor @Observable
final class ResultsModel {
    let tree: FileTree
    let volume: VolumeInfo?
    let asAdministrator: Bool
    init(tree: FileTree, volume: VolumeInfo?, asAdministrator: Bool) { self.tree = tree; self.volume = volume; self.asAdministrator = asAdministrator }
}
