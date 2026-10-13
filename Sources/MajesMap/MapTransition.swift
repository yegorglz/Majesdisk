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
