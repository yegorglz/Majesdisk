import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Quitting mid-scan stops the scan, including a root helper (it watches for its cancel file).
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            if case .scanning(let session) = AppModel.shared.screen { session.cancel() }
            AppModel.shared.saveEditedResults()
        }
    }

    /// A disk or folder dropped on the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        Task { @MainActor in AppModel.shared.startScan(path: url.path, asAdministrator: false) }
    }
}
