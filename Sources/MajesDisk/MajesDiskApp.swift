import AppKit
import MajesCore
import SwiftUI

@main
struct MajesDiskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("MajesDisk", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowToolbarStyle(.unified)
        .commands { MajesCommands() }
        Settings { SettingsView() }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.screen {
            case .overview: OverviewView()
            case .results(let results): ResultsView(results: results)
            }
        }
        .sheet(item: Binding(get: { model.snapshotsVolume }, set: { model.snapshotsVolume = $0 })) { SnapshotsSheet(volume: $0) }
        .onAppear { model.handleLaunchArguments(); DebugSnapshot.scheduleIfRequested() }
    }
}
