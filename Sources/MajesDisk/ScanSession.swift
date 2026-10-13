import MajesCore
import Observation

@MainActor @Observable
final class ScanSession {
    enum State { case running, finished(FileTree), failed(String), cancelled }
    let rootPath: String
    let asAdministrator: Bool
    let volume: VolumeInfo?
    var progress = ScanProgress()
    var state: State = .running
    @ObservationIgnored var onFinish: ((State) -> Void)?

    init(rootPath: String, asAdministrator: Bool, volume: VolumeInfo?) {
        self.rootPath = rootPath; self.asAdministrator = asAdministrator; self.volume = volume
    }
    func start() {}
    func cancel() { state = .cancelled; onFinish?(.cancelled) }
}
