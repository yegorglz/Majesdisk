import Foundation

public struct HelperProgress: Codable, Equatable, Sendable {
    public var files: Int; public var directories: Int; public var bytes: UInt64; public var path: String
}

/// Entry point of `majes-helper`, the CLI the app runs as root through an admin password prompt.
public enum HelperCommand {
    public static let usage: Int32 = 2, cancelled: Int32 = 3, ioError: Int32 = 4

    public static func run(arguments: [String]) -> Int32 {
        guard let command = arguments.first else { return usage }
        switch command {
        case "scan": return scan(options(Array(arguments.dropFirst())))
        default: return usage
        }
    }

    /// `--key value` pairs; anything else lands in "" (positional).
    static func options(_ args: [String]) -> [String: [String]] {
        var out: [String: [String]] = [:]
        var i = 0
        while i < args.count {
            if args[i].hasPrefix("--"), i + 1 < args.count { out[args[i], default: []].append(args[i + 1]); i += 2 }
            else { out["", default: []].append(args[i]); i += 1 }
        }
        return out
    }

    static func scan(_ o: [String: [String]]) -> Int32 {
        guard let root = o["--root"]?.first, let out = o["--out"]?.first,
              let prog = o["--progress"]?.first, let cancel = o["--cancel"]?.first else { return usage }
        let lock = NSLock()
        var lastCheck = Date.distantPast, cancelledFlag = false
        let isCancelled: @Sendable () -> Bool = {
            lock.withLock {
                if !cancelledFlag, Date().timeIntervalSince(lastCheck) >= 0.1 {
                    lastCheck = Date()
                    cancelledFlag = FileManager.default.fileExists(atPath: cancel)
                }
                return cancelledFlag
            }
        }
        let progress: @Sendable (ScanProgress) -> Void = { p in
            let data = try? JSONEncoder().encode(HelperProgress(files: p.files, directories: p.directories, bytes: p.bytes, path: p.currentPath))
            lock.withLock { writeReadable(data ?? Data(), to: prog) }
        }
        let concurrency = ScanOptions.recommendedConcurrency(isSolidState: APFSInfo.diskInfo(mountPath: root)?.isSolidState)
        guard let tree = DiskScanner(options: ScanOptions(rootPath: root, maxConcurrency: concurrency)).run(progress: progress, isCancelled: isCancelled) else {
            return cancelled
        }
        return writeReadable(TreeCodec.encode(tree), to: out) ? 0 : ioError
    }

    /// Root writes these; 0644 lets the non-root app read them.
    @discardableResult
    static func writeReadable(_ data: Data, to path: String) -> Bool {
        guard (try? data.write(to: URL(fileURLWithPath: path), options: .atomic)) != nil else { return false }
        chmod(path, 0o644)
        return true
    }
}
