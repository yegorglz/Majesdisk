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
            }
            Divider()
            CollectorBarView(model: results)
        }
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
                Button { results.rescanFolder(results.center) } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                    .help("Rescan this folder (⌘R)")
                Button { app.showOverview() } label: { Label("Disks", systemImage: "internaldrive") }
                    .help("Back to the disks overview")
            }
        }
    }
}

/// Filled in by Task 14.
struct CollectorBarView: View {
    let model: ResultsModel
    var body: some View { Color.clear.frame(height: 0) }
}
