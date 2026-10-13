import Foundation
import MajesCore

public struct SunburstConfig: Sendable {
    public var maxDepth = 6
    public var centerRadiusFraction = 0.22
    public var minSegmentAngle = 0.0105  // 0.6°: thinner items merge into "smaller objects"
    public init() {}

    public func centerRadius(outerRadius: Double) -> Double { outerRadius * centerRadiusFraction }
    public func ringWidth(outerRadius: Double) -> Double { (outerRadius - centerRadius(outerRadius: outerRadius)) / Double(maxDepth) }
    public func radii(depth: Int, outerRadius: Double) -> (inner: Double, outer: Double) {
        let inner = centerRadius(outerRadius: outerRadius) + Double(depth - 1) * ringWidth(outerRadius: outerRadius)
        return (inner, inner + ringWidth(outerRadius: outerRadius))
    }
}

public enum SegmentKind: Sendable, Equatable { case directory, file, package, restricted, virtual, smallerObjects }

/// One wedge. Angles are radians clockwise from 12 o'clock.
public struct SunburstSegment: Sendable, Equatable {
    /// For `.smallerObjects`: the folder whose tail of children was merged.
    public var node: NodeID
    /// Index into `tree.children(node)` where the merged tail starts.
    public var aggregateStartIndex: Int?
    public var kind: SegmentKind
    public var depth: Int
    public var startAngle: Double
    public var endAngle: Double
    public var midAngle: Double { (startAngle + endAngle) / 2 }

    public init(node: NodeID, aggregateStartIndex: Int?, kind: SegmentKind, depth: Int, startAngle: Double, endAngle: Double) {
        self.node = node; self.aggregateStartIndex = aggregateStartIndex; self.kind = kind
        self.depth = depth; self.startAngle = startAngle; self.endAngle = endAngle
    }
}

public enum SunburstLayout {
    public static func layout(tree: FileTree, center: NodeID, config: SunburstConfig = .init(),
                              expandedPackages: Set<NodeID> = []) -> [SunburstSegment] {
        var out: [SunburstSegment] = []
        func place(_ node: NodeID, _ depth: Int, _ a0: Double, _ a1: Double) {
            let total = Double(tree.size(node))
            guard total > 0 else { return }
            var a = a0
            for (i, c) in tree.children(node).enumerated() {
                let size = tree.size(c)
                if size == 0 { break }  // sorted descending: the rest are empty too
                let span = (a1 - a0) * Double(size) / total
                if span < config.minSegmentAngle {
                    out.append(SunburstSegment(node: node, aggregateStartIndex: i, kind: .smallerObjects, depth: depth, startAngle: a, endAngle: a1))
                    return
                }
                let k = kind(of: c, in: tree)
                out.append(SunburstSegment(node: c, aggregateStartIndex: nil, kind: k, depth: depth, startAngle: a, endAngle: a + span))
                let expandable = k == .directory || k == .virtual || (k == .package && expandedPackages.contains(c))
                if expandable && depth < config.maxDepth { place(c, depth + 1, a, a + span) }
                a += span
            }
        }
        place(center, 1, 0, 2 * .pi)
        return out
    }

    public static func kind(of id: NodeID, in tree: FileTree) -> SegmentKind {
        let f = tree.flags(id)
        if f.contains(.virtual) { return .virtual }
        if f.contains(.restricted) { return .restricted }
        if f.contains(.package) { return .package }
        if f.contains(.directory) { return .directory }
        return .file
    }
}
