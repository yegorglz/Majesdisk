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
            capture(to: path)
            NSApp.terminate(nil)
        }
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
