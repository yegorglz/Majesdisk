import Foundation
import MajesCore

/// Location of the bundled root helper (falls back to the build folder when run unbundled).
enum Helper {
    static var path: String {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/majes-helper").path
        if FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
        return Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("majes-helper").path
    }
}

extension ScanSession {
    /// Runs `majes-helper scan` as root via the password prompt, polling its progress file.
    func startAdministratorScan() {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("MajesDisk-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let out = work.appendingPathComponent("tree.mjd").path
        let prog = work.appendingPathComponent("progress.json").path
        cancelFile = work.appendingPathComponent("cancel").path
        let command = [Helper.path, "scan", "--root", rootPath, "--out", out, "--progress", prog, "--cancel", cancelFile!]
        let poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                if let data = FileManager.default.contents(atPath: prog), let p = try? JSONDecoder().decode(HelperProgress.self, from: data) {
                    self?.progress = ScanProgress(files: p.files, directories: p.directories, bytes: p.bytes, currentPath: p.path)
                }
            }
        }
        Task { [weak self] in
            defer { poller.cancel(); try? FileManager.default.removeItem(at: work) }
            do {
                // Debug: `--debug-no-elevation` runs the same helper pipeline without the password prompt.
                let elevate = !CommandLine.arguments.contains("--debug-no-elevation")
                _ = try await AdminRunner(administrator: elevate, prompt: "MajesDisk wants to scan as administrator.").run(command)
                let tree = try await Task.detached { try TreeCodec.decode(Data(contentsOf: URL(fileURLWithPath: out))) }.value
                await self?.completed(tree)
            } catch AdminRunnerError.cancelled {
                self?.finish(.cancelled)
            } catch AdminRunnerError.failed(let status, let message) {
                // Status 3 = the helper saw our cancel file.
                if status == HelperCommand.cancelled || self?.cancelFlag.value == true { self?.finish(.cancelled) }
                else { self?.finish(.failed(message.isEmpty ? "The administrator scan failed (status \(status))." : message)) }
            } catch {
                self?.finish(.failed("Couldn't read the administrator scan results: \(error.localizedDescription)"))
            }
        }
    }

    /// The root helper polls for this file and stops.
    func cancelAdministratorScan() {
        if let f = cancelFile { FileManager.default.createFile(atPath: f, contents: nil) }
    }
}
