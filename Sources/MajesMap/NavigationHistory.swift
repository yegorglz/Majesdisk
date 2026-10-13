import MajesCore

/// Browser-style back/forward over visited folders.
public struct NavigationHistory: Sendable {
    public private(set) var current: NodeID
    private var back: [NodeID] = []
    private var forward: [NodeID] = []

    public init(start: NodeID) { current = start }
    public var canGoBack: Bool { !back.isEmpty }
    public var canGoForward: Bool { !forward.isEmpty }

    public mutating func visit(_ id: NodeID) {
        guard id != current else { return }
        back.append(current); current = id; forward.removeAll()
    }
    public mutating func goBack() -> NodeID? {
        guard let p = back.popLast() else { return nil }
        forward.append(current); current = p; return p
    }
    public mutating func goForward() -> NodeID? {
        guard let n = forward.popLast() else { return nil }
        back.append(current); current = n; return n
    }
}
