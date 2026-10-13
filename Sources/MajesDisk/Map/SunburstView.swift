import MajesCore
import SwiftUI

struct SunburstView: View {
    let model: ResultsModel

    var body: some View {
        // Reading these here registers Observation dependencies, so the NSView refreshes when they change.
        let token = [Int(model.center), model.treeVersion, model.hovered.map(Int.init) ?? -1,
                     model.hoveredSmallerObjects.map { Int($0.parent) * 31 + $0.start } ?? -1,
                     model.selected.map(Int.init) ?? -1, model.expandedPackages.count, model.collector.items.count]
        SunburstRepresentable(model: model, token: token)
    }
}

private struct SunburstRepresentable: NSViewRepresentable {
    let model: ResultsModel
    let token: [Int]

    func makeNSView(context: Context) -> SunburstNSView {
        let v = SunburstNSView()
        v.model = model
        v.refresh()
        return v
    }

    func updateNSView(_ v: SunburstNSView, context: Context) {
        v.model = model
        v.refresh()
    }
}
