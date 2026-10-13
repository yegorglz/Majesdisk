import AppKit

/// `--snapshot <png> [--snapshot-delay s]`: the app saves its own window to a PNG, then quits.
/// Lets the UI be verified from scripts without Screen Recording permission (own windows only).
enum DebugSnapshot {
    private typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    @MainActor static func scheduleIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let path = args[i + 1]
        let delay = args.firstIndex(of: "--snapshot-delay").flatMap { Double(args[$0 + 1]) } ?? 3
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            try? stateDump().write(toFile: path + ".txt", atomically: true, encoding: .utf8)
            capture(to: path)
            NSApp.terminate(nil)
        }
    }

    /// Text summary of what's on screen; works even when the screen is locked and capture is blank.
    @MainActor static func stateDump() -> String {
        let app = AppModel.shared
        var lines: [String] = []
        switch app.screen {
        case .overview:
            lines.append("screen: overview")
            lines += app.volumes.map { "volume: \($0.name) \($0.mountPath) free=\($0.freeBytes)" }
            lines += app.folderList.map { "folder: \($0) cached=\(app.cachedResults[$0] != nil)" }
        case .scanning(let s):
            lines.append("screen: scanning \(s.rootPath) admin=\(s.asAdministrator) files=\(s.progress.files)")
        case .results(let r):
            lines.append("screen: results \(r.tree.rootPath) admin=\(r.asAdministrator)")
            lines.append("root size=\(r.tree.size(r.tree.root)) items=\(r.tree.itemCount(r.tree.root)) nodes=\(r.tree.nodeCount)")
            lines.append("center: \(r.tree.path(r.center))")
            lines.append("sidebar: " + r.sidebarItems.prefix(8).map { "\(r.displayName($0))=\(r.tree.size($0))" }.joined(separator: ", "))
            lines.append("collector: \(r.collector.items.map(r.tree.path)) deletion=\(r.deletion.phase)")
            if let a = r.alert { lines.append("alert: \(a.title) — \(a.message)") }
        }
        lines.append("cached: \(app.cachedResults.keys.sorted())")
        return lines.joined(separator: "\n") + "\n"
    }

    @MainActor static func capture(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.windowNumber > 0 }) else { return }
        // shortcut: CGWindowListCreateImage is obsoleted in the SDK but still exported; debug-only use.
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") {
            let create = unsafeBitCast(sym, to: CreateImage.self)
            // .null rect, optionIncludingWindow (8), boundsIgnoreFraming (1)
            if let image = create(.null, 8, UInt32(window.windowNumber), 1)?.takeRetainedValue() {
                let rep = NSBitmapImageRep(cgImage: image)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                return
            }
        }
        if let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }
}
