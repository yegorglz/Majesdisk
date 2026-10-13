import MajesCore
import SwiftUI

/// Path from the scanned root to the map center; each part navigates there.
struct BreadcrumbView: View {
    let model: ResultsModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(chain.enumerated()), id: \.element) { i, id in
                if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary) }
                Button(model.displayName(id)) { model.navigate(to: id) }
                    .buttonStyle(.plain)
                    .font(i == chain.count - 1 ? .callout.bold() : .callout)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: 520)
    }

    var chain: [NodeID] {
        var out: [NodeID] = [model.center]
        while let p = model.tree.parent(out[0]) { out.insert(p, at: 0) }
        return out
    }
}
