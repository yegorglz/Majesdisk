import SwiftUI

struct ResultsView: View {
    let results: ResultsModel
    var body: some View { Text(results.tree.rootPath) }
}
