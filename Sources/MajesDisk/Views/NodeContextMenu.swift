import MajesCore
import SwiftUI

/// Filled in by Task 12.
struct NodeContextMenu: View {
    let model: ResultsModel
    let id: NodeID
    var body: some View { Button("Reveal in Finder") { model.reveal(id) } }
}
