import MajesCore
import SwiftUI

struct ResultsView: View {
    @Environment(AppModel.self) private var app
    let results: ResultsModel

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                SidebarView(model: results).frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
                SunburstView(model: results).frame(minWidth: 420)
                    // A folder or disk dragged in from Finder starts a new scan; internal drags are ignored.
                    .dropDestination(for: URL.self) { urls, _ in
                        var isDir: ObjCBool = false
                        guard let url = urls.first(where: { $0.isFileURL && FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDir) && isDir.boolValue })
                        else { return false }
                        app.startScan(path: url.path, asAdministrator: false)
                        return true
                    }
                    .overlay(alignment: .topTrailing) {
                        if results.isRescanning {
                            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Rescanning…") }
                                .padding(8).background(.regularMaterial, in: Capsule()).padding(12)
                        }
                    }
            }
            Divider()
            CollectorBarView(model: results)
        }
        .alert(results.alert?.title ?? "", isPresented: Binding(get: { results.alert != nil }, set: { if !$0 { results.alert = nil } }),
               presenting: results.alert) { info in
            if !info.adminRetryPaths.isEmpty {
                Button("Delete as Administrator") { results.deleteAsAdministrator(info.adminRetryPaths) }
            }
            Button("OK", role: .cancel) {}
        } message: { info in Text(info.message) }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { results.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!results.history.canGoBack).help("Back (⌘[)")
                Button { results.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!results.history.canGoForward).help("Forward (⌘])")
                Button { results.goUp() } label: { Image(systemName: "arrow.up") }
                    .disabled(results.tree.parent(results.center) == nil).help("Enclosing folder (⌘↑)")
            }
            ToolbarItem(placement: .principal) { BreadcrumbView(model: results) }
            ToolbarItemGroup(placement: .primaryAction) {
                if !results.staleFolders.isEmpty {
                    Button { results.rescanChanged() } label: {
                        Label("Rescan Changed (\(results.staleFolders.count))", systemImage: "exclamationmark.arrow.circlepath")
                    }
                    .labelStyle(.titleAndIcon)
                    .help("Some folders changed outside MajesDisk since the scan. Re-measure just those.")
                }
                Button { results.rescanFolder(results.center) } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                    .help("Rescan this folder (⌘R)")
                Button { app.showOverview() } label: { Label("Disks", systemImage: "internaldrive") }
                    .help("Back to the disks overview")
            }
        }
    }
}
