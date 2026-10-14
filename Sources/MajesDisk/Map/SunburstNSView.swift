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
    /// The entered folder's wedge (zoom in, from the old map) or the left folder's wedge (zoom out, in the
    /// new map): children grow out of it / shrink back into it. Nil (e.g. breadcrumb jumps) → plain cross-fade.
    private var morphSpan: (start: Double, end: Double, depth: Int)?
    private var timer: Timer?

    private var magnifyAccumulator: CGFloat = 0
    private var mouseDownPoint: NSPoint?
    var dragStarted = false

    override var isFlipped: Bool { true }
    private var baseLayer: CGLayer?
    private var baseKey: [Int] = []

    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); baseLayer = nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); baseLayer = nil }
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
        if let shown = shownCenter, shown != model.center, !segments.isEmpty,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            oldSegments = segments
            transitionDirection = model.transition
            let anchor = transitionDirection == .zoomIn
                ? oldSegments.first { $0.node == model.center && $0.kind != .smallerObjects }
                : model.segments.first { $0.node == shown && $0.kind != .smallerObjects }
            morphSpan = anchor.map { ($0.startAngle, $0.endAngle, $0.depth) }
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
        updateAccessibility(model)
        needsDisplay = true
    }

    /// VoiceOver can't read wedges; it gets the folder and the pointed item, and the sidebar lists the rest.
    private func updateAccessibility(_ model: ResultsModel) {
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        var label = "Disk map of \(model.displayName(model.center)), \(ByteFormat.string(model.tree.size(model.center)))"
        if let p = model.hovered ?? model.rowHovered ?? model.selected {
            label += ". Pointing at \(model.displayName(p)), \(ByteFormat.string(model.tree.size(p)))"
        }
        setAccessibilityLabel(label)
        setAccessibilityHelp("The list beside the map shows the same items. Return opens a folder; Command-Up goes to the enclosing folder.")
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
            let e = f.incomingAlpha  // eased progress
            if let span = morphSpan, transitionDirection == .zoomIn {
                draw(oldSegments, in: ctx, model: model, scale: 1, alpha: 1 - e, highlight: nil)
                drawMorphed(segments, from: span, progress: e, in: ctx, model: model)
            } else if let span = morphSpan {
                draw(segments, in: ctx, model: model, scale: 1, alpha: e, highlight: nil)
                drawMorphed(oldSegments, from: span, progress: 1 - e, in: ctx, model: model)
            } else {
                draw(oldSegments, in: ctx, model: model, scale: f.outgoingScale, alpha: f.outgoingAlpha, highlight: nil)
                draw(segments, in: ctx, model: model, scale: f.incomingScale, alpha: f.incomingAlpha, highlight: nil)
            }
        } else {
            // Hovering redraws only one wedge: the rest comes from a cached layer.
            let key = [Int(model.center), model.treeVersion, model.collector.items.hashValue]
            if baseLayer == nil || key != baseKey, let layer = CGLayer(ctx, size: bounds.size, auxiliaryInfo: nil), let lctx = layer.context {
                draw(segments, in: lctx, model: model, scale: 1, alpha: 1, highlight: nil)
                shadeDepth(segments, in: lctx)
                baseLayer = layer
                baseKey = key
            }
            if let baseLayer { ctx.draw(baseLayer, at: .zero) }
            if let i = hoveredIndex {
                ctx.saveGState()
                ctx.setShadow(offset: .zero, blur: 14, color: SunburstPalette.color(for: segments[i], highlighted: true).nsColor.withAlphaComponent(0.9).cgColor)
                draw([segments[i]], in: ctx, model: model, scale: 1, alpha: 1, highlight: 0)
                ctx.restoreGState()
            }
        }
        drawCenter(model: model)
    }

    private func draw(_ segs: [SunburstSegment], in ctx: CGContext, model: ResultsModel, scale: Double, alpha: Double, highlight: Int?) {
        ctx.saveGState()
        ctx.translateBy(x: mapCenter.x, y: mapCenter.y)
        ctx.scaleBy(x: scale, y: scale)
        ctx.setAlpha(alpha)
        ctx.setStrokeColor(NSColor.windowBackgroundColor.cgColor)
        ctx.setLineWidth(1.5 / scale)  // background-colored stroke = a clean gap between wedges
        for (i, s) in segs.enumerated() {
            let path = wedge(s, outer: outerRadius)
            var color = SunburstPalette.color(for: s, highlighted: i == highlight)
            if s.kind != .smallerObjects, model.collector.contains(s.node) { color.a *= 0.35 }
            ctx.addPath(path)
            ctx.setFillColor(color.nsColor.cgColor)
            ctx.drawPath(using: .eoFillStroke)  // even-odd keeps full-circle rings hollow
        }
        ctx.restoreGState()
    }

    /// Darkens rings gently toward the rim so the map reads as depth, not a flat chart. Drawn once into the cache.
    private func shadeDepth(_ segs: [SunburstSegment], in ctx: CGContext) {
        guard !segs.isEmpty else { return }
        ctx.saveGState()
        ctx.translateBy(x: mapCenter.x, y: mapCenter.y)
        for s in segs { ctx.addPath(wedge(s, outer: outerRadius)) }
        ctx.clip(using: .evenOdd)
        let r0 = config.centerRadius(outerRadius: outerRadius)
        let colors = [NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.withAlphaComponent(0.22).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawRadialGradient(g, startCenter: .zero, startRadius: r0, endCenter: .zero, endRadius: outerRadius, options: [])
        }
        ctx.restoreGState()
    }

    private var iconCache: [String: NSImage] = [:]
    private func icon(for path: String) -> NSImage {
        if let i = iconCache[path] { return i }
        let i = NSWorkspace.shared.icon(forFile: path)
        if iconCache.count > 200 { iconCache.removeAll() }
        iconCache[path] = i
        return i
    }

    /// Segments mid-morph, clipped to the map's outer circle (deep rings start outside it).
    private func drawMorphed(_ segs: [SunburstSegment], from span: (start: Double, end: Double, depth: Int), progress: Double,
                             in ctx: CGContext, model: ResultsModel) {
        ctx.saveGState()
        ctx.translateBy(x: mapCenter.x, y: mapCenter.y)
        ctx.addEllipse(in: CGRect(x: -outerRadius, y: -outerRadius, width: 2 * outerRadius, height: 2 * outerRadius))
        ctx.clip()
        ctx.setStrokeColor(NSColor.windowBackgroundColor.cgColor)
        ctx.setLineWidth(1.5)
        for s in segs {
            let m = MapTransition.morph(s, from: span, progress: progress)
            var shown = s
            (shown.startAngle, shown.endAngle, shown.depth) = (m.startAngle, m.endAngle, Int(m.depth.rounded()))
            var color = SunburstPalette.color(for: shown, highlighted: false)
            if s.kind != .smallerObjects, model.collector.contains(s.node) { color.a *= 0.35 }
            ctx.addPath(wedge(start: m.startAngle, end: m.endAngle, depth: m.depth, outer: outerRadius))
            ctx.setFillColor(color.nsColor.cgColor)
            ctx.drawPath(using: .eoFillStroke)
        }
        ctx.restoreGState()
    }

    /// Annular wedge around the origin; angle θ clockwise from 12 o'clock maps to CG angle θ − π/2 in y-down space.
    func wedge(_ s: SunburstSegment, outer: Double) -> CGPath {
        wedge(start: s.startAngle, end: s.endAngle, depth: Double(s.depth), outer: outer)
    }

    /// `depth` may be fractional while morphing.
    func wedge(start: Double, end: Double, depth: Double, outer: Double) -> CGPath {
        let w = config.ringWidth(outerRadius: outer)
        let r = (inner: config.centerRadius(outerRadius: outer) + (depth - 1) * w, outer: config.centerRadius(outerRadius: outer) + depth * w)
        let a0 = start - .pi / 2, a1 = end - .pi / 2
        let p = CGMutablePath()
        if end - start >= 2 * .pi - 1e-9 {
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
        var iconPath: String?
        if let r = model.hoveredSmallerObjects {
            let items = tree.children(r.parent).dropFirst(r.start)
            shown = ("\(items.count) smaller objects", items.reduce(0) { $0 + tree.size($1) })
        } else {
            let id = model.hovered ?? model.rowHovered ?? model.center
            shown = (model.displayName(id), tree.size(id))
            if tree.virtualKind(id) == nil { iconPath = tree.path(id) }
        }
        let iconSide = min(30, r0 * 0.42)
        if let iconPath, r0 > 46 {
            icon(for: iconPath).draw(in: CGRect(x: mapCenter.x - iconSide / 2, y: mapCenter.y - 24 - iconSide - 2, width: iconSide, height: iconSide),
                                     from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byTruncatingMiddle
        let nameAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.labelColor, .paragraphStyle: para]
        let rounded = NSFont.systemFont(ofSize: 19, weight: .semibold).fontDescriptor.withDesign(.rounded)
        let sizeFont = rounded.flatMap { NSFont(descriptor: $0, size: 19) } ?? NSFont.monospacedDigitSystemFont(ofSize: 19, weight: .semibold)
        let sizeAttrs: [NSAttributedString.Key: Any] = [.font: sizeFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: para]
        let w = r0 * 1.6
        (shown.0 as NSString).draw(with: CGRect(x: mapCenter.x - w / 2, y: mapCenter.y - 22, width: w, height: 18), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: nameAttrs)
        (ByteFormat.string(shown.1) as NSString).draw(with: CGRect(x: mapCenter.x - w / 2, y: mapCenter.y - 1, width: w, height: 26), options: [.usesLineFragmentOrigin], attributes: sizeAttrs)
        if model.tree.parent(model.center) != nil {
            let up = NSAttributedString(string: "▲", attributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.secondaryLabelColor])
            up.draw(at: CGPoint(x: mapCenter.x - up.size().width / 2, y: mapCenter.y + 30))  // "click to go up", below the size
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
            // The mouse now points somewhere else; a stale keyboard selection must not receive ⌘⌫.
            if model.selected != nil, model.selected != model.hovered { model.selected = nil }
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

    /// Drags a wedge toward the Collector. The pasteboard carries an app-internal URL, so dropping
    /// on Finder never copies files.
    func beginDrag(from point: NSPoint, event: NSEvent) {
        guard let model, case .segment(let i) = SunburstHitTest.hit(point: point, center: mapCenter, outerRadius: outerRadius, segments: segments, config: config),
              segments[i].kind != .smallerObjects else { return }
        let s = segments[i]
        let item = NSDraggingItem(pasteboardWriter: ResultsModel.dragURL(for: s.node) as NSURL)
        item.setDraggingFrame(CGRect(x: point.x - 32, y: point.y - 32, width: 64, height: 64), contents: dragImage(s, model: model))
        beginDraggingSession(with: [item], event: event, source: self)
    }

    private func dragImage(_ s: SunburstSegment, model: ResultsModel) -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: rect.midX, y: rect.midY)
            let r = self.config.radii(depth: s.depth, outerRadius: self.outerRadius)
            let scale = 30 / r.outer
            ctx.scaleBy(x: scale, y: scale)
            ctx.addPath(self.wedge(s, outer: self.outerRadius))
            ctx.setFillColor(SunburstPalette.color(for: s, highlighted: true).nsColor.cgColor)
            ctx.fillPath()
            return true
        }
    }
}

extension SunburstNSView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .copy : []
    }
}
