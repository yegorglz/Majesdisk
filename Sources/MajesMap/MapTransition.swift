public enum TransitionDirection: Sendable { case zoomIn, zoomOut }

public struct TransitionFrame: Equatable, Sendable {
    public var outgoingScale, outgoingAlpha, incomingScale, incomingAlpha: Double
    public init(outgoingScale: Double, outgoingAlpha: Double, incomingScale: Double, incomingAlpha: Double) {
        self.outgoingScale = outgoingScale; self.outgoingAlpha = outgoingAlpha
        self.incomingScale = incomingScale; self.incomingAlpha = incomingAlpha
    }
}

/// Zoom cross-fade between two map levels.
public enum MapTransition {
    public static let duration = 0.3

    public static func frame(t: Double, direction: TransitionDirection) -> TransitionFrame {
        let c = min(1, max(0, t)), e = c * c * (3 - 2 * c)
        switch direction {
        case .zoomIn:
            return TransitionFrame(outgoingScale: 1 + 0.5 * e, outgoingAlpha: 1 - e, incomingScale: 0.6 + 0.4 * e, incomingAlpha: e)
        case .zoomOut:
            return TransitionFrame(outgoingScale: 1 - 0.4 * e, outgoingAlpha: 1 - e, incomingScale: 1.5 - 0.5 * e, incomingAlpha: e)
        }
    }
}

/// A wedge partway through a drill-in/out morph; depth is fractional (ring index).
public struct MorphedSegment: Equatable, Sendable {
    public var startAngle: Double, endAngle: Double, depth: Double
}

extension MapTransition {
    /// DaisyDisk-style morph: at progress 0 a child of the entered folder sits inside that folder's
    /// old wedge (`span`), one ring further out per level; at 1 it is at its own layout position.
    public static func morph(_ s: SunburstSegment, from span: (start: Double, end: Double, depth: Int), progress: Double) -> MorphedSegment {
        let p = min(1, max(0, progress))
        let width = span.end - span.start
        let a0 = span.start + s.startAngle / (2 * .pi) * width
        let a1 = span.start + s.endAngle / (2 * .pi) * width
        let d0 = Double(s.depth + span.depth)
        return MorphedSegment(startAngle: a0 + (s.startAngle - a0) * p, endAngle: a1 + (s.endAngle - a1) * p,
                              depth: d0 + (Double(s.depth) - d0) * p)
    }
}
