import MajesCore
import SwiftUI

struct SunburstView: View {
    let model: ResultsModel

    /// Reading these registers Observation dependencies, so the NSView refreshes when any changes.
    private var token: [Int] {
        var t: [Int] = [Int(model.center), model.treeVersion, model.expandedPackages.count, model.collector.items.count]
        t.append(model.hovered.map { Int($0) } ?? -1)
        t.append(model.rowHovered.map { Int($0) } ?? -1)
        t.append(model.selected.map { Int($0) } ?? -1)
        t.append(model.hoveredSmallerObjects.map { Int($0.parent) * 31 + $0.start } ?? -1)
        return t
    }

    var body: some View { SunburstRepresentable(model: model, token: token) }
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
