import Foundation
import MajesCore

/// Location of the bundled root helper (falls back to the build folder when run unbundled).
enum Helper {
    static var pathOverride: String?  // tests
    static var path: String {
        if let pathOverride { return pathOverride }
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/majes-helper").path
        if FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
        return Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("majes-helper").path
    }

    /// Debug: `--debug-no-elevation` runs the same helper pipeline without the password prompt.
    static var elevate = !CommandLine.arguments.contains("--debug-no-elevation")
}

/// One `majes-helper scan` run as root: progress is polled from a file, cancel is a file the helper watches.
@MainActor
final class HelperScan {
    private let work = FileManager.default.temporaryDirectory.appendingPathComponent("MajesDisk-\(UUID().uuidString)")
    private var cancelPath: String { work.appendingPathComponent("cancel").path }

    func cancel() { FileManager.default.createFile(atPath: cancelPath, contents: nil) }

    /// Returns nil when cancelled (by the user at the password prompt or via `cancel()`).
    func run(root: String, prompt: String, progress: @escaping @MainActor (ScanProgress) -> Void) async throws -> FileTree? {
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let out = work.appendingPathComponent("tree.mjd").path
        let prog = work.appendingPathComponent("progress.json").path
        let poller = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                if let data = FileManager.default.contents(atPath: prog), let p = try? JSONDecoder().decode(HelperProgress.self, from: data) {
                    progress(ScanProgress(files: p.files, directories: p.directories, bytes: p.bytes, currentPath: p.path))
                }
            }
        }
        defer { poller.cancel() }
        do {
            _ = try await AdminRunner(administrator: Helper.elevate, prompt: prompt)
                .run([Helper.path, "scan", "--root", root, "--out", out, "--progress", prog, "--cancel", cancelPath])
        } catch AdminRunnerError.cancelled {
            return nil
        } catch AdminRunnerError.failed(let status, _) where status == HelperCommand.cancelled {
            return nil
        }
        return try await Task.detached { try TreeCodec.decode(Data(contentsOf: URL(fileURLWithPath: out))) }.value
    }
}

extension ScanSession {
    func startAdministratorScan() {
        let scan = HelperScan()
        helperScan = scan
        Task { [weak self] in
            guard let root = self?.rootPath else { return }
            do {
                let tree = try await scan.run(root: root, prompt: "MajesDisk wants to scan as administrator.") { self?.progress = $0 }
                if let tree { await self?.completed(tree) } else { self?.finish(.cancelled) }
            } catch AdminRunnerError.failed(let status, let message) {
                if self?.cancelFlag.value == true { self?.finish(.cancelled); return }
                self?.finish(.failed(message.isEmpty ? "The administrator scan failed (status \(status))." : message))
            } catch {
                self?.finish(.failed("Couldn't read the administrator scan results: \(error.localizedDescription)"))
            }
        }
    }

    /// The root helper polls for its cancel file and stops.
    func cancelAdministratorScan() { helperScan?.cancel() }
}
