import AppKit
import MajesCore
import MajesMap

/// Draws the ring map with Core Graphics and turns mouse, trackpad and keys into navigation.
/// Flipped (y-down) so drawing and `SunburstHitTest` share one angle convention.
final class SunburstNSView: NSView {
    weak var model: ResultsModel?
    let config = SunburstConfig()
    private(set) var segments: [SunburstSegment] = []
    private var shownCenter: NodeID?
    private var hoveredIndex: Int?

    // Transition state
    private var oldSegments: [SunburstSegment] = []
    private var transitionStart: Date?
    private var transitionDirection: TransitionDirection = .zoomIn
    private var timer: Timer?

    private var magnifyAccumulator: CGFloat = 0
    private var mouseDownPoint: NSPoint?
    var dragStarted = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    var outerRadius: Double { max(40, Double(min(bounds.width, bounds.height)) / 2 - 16) }
    var mapCenter: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    /// Called whenever the model changes; recomputes the layout only when its inputs changed.
    func refresh() {
        guard let model else { return }
        if let shown = shownCenter, shown != model.center, !segments.isEmpty {
            oldSegments = segments
            transitionDirection = model.transition
            startTransition()
        }
        shownCenter = model.center
        segments = model.segments
        hoveredIndex = segments.firstIndex { s in
            if let h = model.hovered ?? model.rowHovered { return s.kind != .smallerObjects && s.node == h }
            if let r = model.hoveredSmallerObjects { return s.kind == .smallerObjects && s.node == r.parent && s.aggregateStartIndex == r.start }
            if let sel = model.selected { return s.kind != .smallerObjects && s.node == sel }
            return false
        }
        needsDisplay = true
    }

    private func startTransition() {
        transitionStart = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] t in
            guard let self, let start = self.transitionStart else { t.invalidate(); return }
            if Date().timeIntervalSince(start) >= MapTransition.duration { self.transitionStart = nil; self.oldSegments = []; t.invalidate() }
            self.needsDisplay = true
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let model else { return }
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        if let start = transitionStart {
            let f = MapTransition.frame(t: Date().timeIntervalSince(start) / MapTransition.duration, direction: transitionDirection)
            draw(oldSegments, in: ctx, model: model, scale: f.outgoingScale, alpha: f.outgoingAlpha, highlight: nil)
            draw(segments, in: ctx, model: model, scale: f.incomingScale, alpha: f.incomingAlpha, highlight: nil)
        } else {
            draw(segments, in: ctx, model: model, scale: 1, alpha: 1, highlight: hoveredIndex)
        }
        drawCenter(model: model)
    }

    private func draw(_ segs: [SunburstSegment], in ctx: CGContext, model: ResultsModel, scale: Double, alpha: Double, highlight: Int?) {
        ctx.saveGState()
        ctx.translateBy(x: mapCenter.x, y: mapCenter.y)
        ctx.scaleBy(x: scale, y: scale)
        ctx.setAlpha(alpha)
        ctx.setStrokeColor(NSColor.windowBackgroundColor.cgColor)
        ctx.setLineWidth(0.75 / scale)
        for (i, s) in segs.enumerated() {
            let path = wedge(s, outer: outerRadius)
            var color = SunburstPalette.color(for: s, highlighted: i == highlight)
            if s.kind != .smallerObjects, model.collector.contains(s.node) { color.a *= 0.35 }
            ctx.addPath(path)
            ctx.setFillColor(color.nsColor.cgColor)
            ctx.drawPath(using: .fillStroke)
        }
        ctx.restoreGState()
    }

    /// Annular wedge around the origin; angle θ clockwise from 12 o'clock maps to CG angle θ − π/2 in y-down space.
    func wedge(_ s: SunburstSegment, outer: Double) -> CGPath {
        let r = config.radii(depth: s.depth, outerRadius: outer)
        let a0 = s.startAngle - .pi / 2, a1 = s.endAngle - .pi / 2
        let p = CGMutablePath()
        if s.endAngle - s.startAngle >= 2 * .pi - 1e-9 {
            p.addEllipse(in: CGRect(x: -r.outer, y: -r.outer, width: 2 * r.outer, height: 2 * r.outer))
            p.addEllipse(in: CGRect(x: -r.inner, y: -r.inner, width: 2 * r.inner, height: 2 * r.inner))
            return p
        }
        p.addArc(center: .zero, radius: r.outer, startAngle: a0, endAngle: a1, clockwise: false)
        p.addArc(center: .zero, radius: r.inner, startAngle: a1, endAngle: a0, clockwise: true)
        p.closeSubpath()
        return p
    }

    private func drawCenter(model: ResultsModel) {
        let r0 = config.centerRadius(outerRadius: outerRadius)
        let rect = CGRect(x: mapCenter.x - r0, y: mapCenter.y - r0, width: 2 * r0, height: 2 * r0)
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()

        let tree = model.tree
        let shown: (String, UInt64)
        if let r = model.hoveredSmallerObjects {
            let items = tree.children(r.parent).dropFirst(r.start)
            shown = ("\(items.count) smaller objects", items.reduce(0) { $0 + tree.size($1) })
        } else {
            let id = model.hovered ?? model.rowHovered ?? model.center
            shown = (model.displayName(id), tree.size(id))
        }
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byTruncatingMiddle
        let nameAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.labelColor, .paragraphStyle: para]
        let sizeAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 17, weight: .regular), .foregroundColor: NSColor.labelColor, .paragraphStyle: para]
        let w = r0 * 1.6
        (shown.0 as NSString).draw(with: CGRect(x: mapCenter.x - w / 2, y: mapCenter.y - 22, width: w, height: 18), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: nameAttrs)
        (ByteFormat.string(shown.1) as NSString).draw(with: CGRect(x: mapCenter.x - w / 2, y: mapCenter.y, width: w, height: 22), options: [.usesLineFragmentOrigin], attributes: sizeAttrs)
        if model.tree.parent(model.center) != nil {
            let up = NSAttributedString(string: "▲", attributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.secondaryLabelColor])
            up.draw(at: CGPoint(x: mapCenter.x - up.size().width / 2, y: mapCenter.y - r0 + 10))
        }
    }

    // MARK: Mouse

    func hit(_ event: NSEvent) -> HitResult {
        SunburstHitTest.hit(point: convert(event.locationInWindow, from: nil), center: mapCenter, outerRadius: outerRadius, segments: segments, config: config)
    }

    override func mouseMoved(with event: NSEvent) {
        guard let model, transitionStart == nil else { return }
        switch hit(event) {
        case .segment(let i):
            let s = segments[i]
            if s.kind == .smallerObjects {
                let ref = SmallerObjectsRef(parent: s.node, start: s.aggregateStartIndex ?? 0)
                if model.hoveredSmallerObjects != ref { model.hovered = nil; model.hoveredSmallerObjects = ref }
            } else if model.hovered != s.node || model.hoveredSmallerObjects != nil {
                model.hoveredSmallerObjects = nil; model.hovered = s.node
            }
        default:
            if model.hovered != nil || model.hoveredSmallerObjects != nil { model.hovered = nil; model.hoveredSmallerObjects = nil }
        }
        NSCursor.arrow.set()
    }

    // Hover stays "sticky" when the mouse leaves the map, so the sidebar keeps the pointed folder's list.
    override func mouseExited(with event: NSEvent) {}

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        dragStarted = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, !dragStarted else { return }
        let p = convert(event.locationInWindow, from: nil)
        if hypot(p.x - start.x, p.y - start.y) > 4 { dragStarted = true; beginDrag(from: start, event: event) }
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownPoint = nil }
        guard let model, !dragStarted else { return }
        switch hit(event) {
        case .center:
            model.goUp()
        case .segment(let i):
            let s = segments[i]
            if event.modifierFlags.contains(.command) {
                model.reveal(s.kind == .smallerObjects ? s.node : s.node)
            } else if s.kind == .smallerObjects {
                model.expandSmallerObjects(SmallerObjectsRef(parent: s.node, start: s.aggregateStartIndex ?? 0))
            } else if model.isContainer(s.node) {
                model.enter(s.node)
            } else {
                model.selected = s.node
            }
        case .none:
            break
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model, case .segment(let i) = hit(event), segments[i].kind != .smallerObjects else { return nil }
        model.hovered = segments[i].node
        return NodeAction.menu(model: model, id: segments[i].node)
    }

    override func magnify(with event: NSEvent) {
        guard let model else { return }
        if event.phase == .began { magnifyAccumulator = 0 }
        magnifyAccumulator += event.magnification
        if magnifyAccumulator > 0.3 {
            magnifyAccumulator = 0
            if let r = model.hoveredSmallerObjects { model.expandSmallerObjects(r) } else if let h = model.hovered { model.enter(h) }
        } else if magnifyAccumulator < -0.3 {
            magnifyAccumulator = 0
            model.goUp()
        }
    }

    override func keyDown(with event: NSEvent) {
        let f = event.modifierFlags
        var mods: KeyModifiers = []
        if f.contains(.command) { mods.insert(.command) }
        if f.contains(.shift) { mods.insert(.shift) }
        if f.contains(.option) { mods.insert(.option) }
        if f.contains(.control) { mods.insert(.control) }
        if let action = KeyBindings.action(keyCode: event.keyCode, modifiers: mods), let model {
            model.perform(action)
        } else {
            super.keyDown(with: event)
        }
    }

    /// Wired to the Collector in Task 14.
    func beginDrag(from point: NSPoint, event: NSEvent) {}
}
