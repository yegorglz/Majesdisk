import Foundation

public struct ScanProgress: Sendable, Equatable {
    public var files = 0
    public var directories = 0
    public var bytes: UInt64 = 0
    public var currentPath = ""
    public init(files: Int = 0, directories: Int = 0, bytes: UInt64 = 0, currentPath: String = "") {
        self.files = files; self.directories = directories; self.bytes = bytes; self.currentPath = currentPath
    }
}

public struct ScanOptions: Sendable {
    public var rootPath: String
    public var maxConcurrency: Int
    public init(rootPath: String, maxConcurrency: Int = 8) { self.rootPath = rootPath; self.maxConcurrency = maxConcurrency }
    /// Spinning disks get one reader so the head doesn't thrash between parallel requests.
    public static func recommendedConcurrency(isSolidState: Bool?) -> Int { isSolidState == false ? 1 : 8 }
}

/// Walks a folder tree with N parallel directory readers; tree assembly is serialized under one lock.
public final class DiskScanner: @unchecked Sendable {
    let options: ScanOptions
    let reader: DirectoryReading

    public init(options: ScanOptions, reader: DirectoryReading = BulkDirectoryReader()) {
        self.options = options; self.reader = reader
    }

    /// Blocking; call off the main thread. Returns nil when cancelled.
    public func run(progress: @escaping @Sendable (ScanProgress) -> Void = { _ in },
                    isCancelled: @escaping @Sendable () -> Bool = { false }) -> FileTree? {
        let builder = FileTreeBuilder(rootPath: options.rootPath)
        let cv = NSCondition()
        var stack: [(NodeID, String)] = [(builder.root, options.rootPath)]
        var inFlight = 0
        var stats = ScanProgress()
        var lastEmit = Date.distantPast

        DispatchQueue.concurrentPerform(iterations: max(1, options.maxConcurrency)) { _ in
            while true {
                cv.lock()
                while stack.isEmpty && inFlight > 0 && !isCancelled() { cv.wait(until: Date(timeIntervalSinceNow: 0.05)) }
                if stack.isEmpty || isCancelled() { cv.broadcast(); cv.unlock(); return }
                let (id, path) = stack.removeLast()
                inFlight += 1
                cv.unlock()

                let result = reader.read(path: path)

                cv.lock()
                switch result {
                case .failed:
                    builder.markRestricted(id)
                case .entries(let entries):
                    let ids = builder.appendChildren(of: id, entries: entries)
                    let base = path.hasSuffix("/") ? path : path + "/"
                    for (e, cid) in zip(entries, ids) {
                        if e.kind == .directory {
                            if !e.isMountPoint { stack.append((cid, base + e.name)) }
                        } else {
                            stats.files += 1
                            stats.bytes += e.allocatedSize
                        }
                    }
                }
                stats.directories += 1
                stats.currentPath = path
                inFlight -= 1
                let now = Date()
                let emit = now.timeIntervalSince(lastEmit) >= 0.1 || (stack.isEmpty && inFlight == 0)
                if emit { lastEmit = now }
                let snapshot = stats
                cv.broadcast()
                cv.unlock()
                if emit { progress(snapshot) }
            }
        }
        return isCancelled() ? nil : builder.finish()
    }
}
