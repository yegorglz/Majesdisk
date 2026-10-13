import SwiftUI

struct ResultsView: View {
    let results: ResultsModel
    var body: some View { SunburstView(model: results) }
}
