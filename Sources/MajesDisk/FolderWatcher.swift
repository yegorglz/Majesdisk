import CoreServices
import Foundation

/// File-system events under one folder (FSEvents), delivered in batches on the main queue.
/// Starting from an event ID taken when the scan began also replays changes made during the scan.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let handler: ([String]) -> Void

    init?(path: String, since: FSEventStreamEventId, handler: @escaping ([String]) -> Void) {
        self.handler = handler
        var context = FSEventStreamContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        context.info = Unmanaged.passUnretained(self).toOpaque()
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let me = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let all = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            me.handler(all.indices.filter { FolderWatcher.isContentChange(flags[$0]) }.map { all[$0] })
        }
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        guard let s = FSEventStreamCreate(nil, callback, &context, [path] as CFArray, since, 0.5, flags) else { return nil }
        stream = s
        FSEventStreamSetDispatchQueue(s, .main)
        FSEventStreamStart(s)
    }

    /// Created, removed, renamed or written — not history markers, root moves, or metadata touches.
    static func isContentChange(_ f: FSEventStreamEventFlags) -> Bool {
        let content = kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved
            | kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagItemModified
        let ignore = kFSEventStreamEventFlagHistoryDone | kFSEventStreamEventFlagRootChanged
        return Int(f) & ignore == 0 && Int(f) & content != 0
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s)
        stream = nil
    }

    deinit { stop() }
}
