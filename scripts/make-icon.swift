// Renders the MajesDisk app icon — an eye whose iris is the disk map — into an .iconset folder.
// Usage: swift scripts/make-icon.swift <out.iconset> [preview.png]
import AppKit

let out = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px)
    let rgb = CGColorSpaceCreateDeviceRGB()
    func gradient(_ a: NSColor, _ b: NSColor) -> CGGradient {
        CGGradient(colorsSpace: rgb, colors: [a.cgColor, b.cgColor] as CFArray, locations: [0, 1])!
    }

    // Tile: macOS icon grid (824/1024 body), deep ink-blue night.
    let inset = s * 0.098, side = s - 2 * inset
    let tile = CGPath(roundedRect: CGRect(x: inset, y: inset, width: side, height: side), cornerWidth: side * 0.225, cornerHeight: side * 0.225, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    ctx.addPath(tile); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(tile); ctx.clip()
    ctx.drawLinearGradient(gradient(NSColor(srgbRed: 0.12, green: 0.13, blue: 0.24, alpha: 1), NSColor(srgbRed: 0.03, green: 0.03, blue: 0.08, alpha: 1)),
                           start: CGPoint(x: 0, y: inset + side), end: CGPoint(x: 0, y: inset), options: [])

    // Eye: an almond made of two arcs, wider than tall.
    let c = CGPoint(x: s / 2, y: s / 2)
    let halfW = side * 0.43, halfH = side * 0.25
    let eye = CGMutablePath()
    eye.move(to: CGPoint(x: c.x - halfW, y: c.y))
    eye.addQuadCurve(to: CGPoint(x: c.x + halfW, y: c.y), control: CGPoint(x: c.x, y: c.y + halfH * 2))
    eye.addQuadCurve(to: CGPoint(x: c.x - halfW, y: c.y), control: CGPoint(x: c.x, y: c.y - halfH * 2))
    eye.closeSubpath()

    // Soft glow around the eye, then the white of the eye with a shaded upper lid.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.06, color: NSColor(srgbRed: 0.55, green: 0.65, blue: 1, alpha: 0.35).cgColor)
    ctx.addPath(eye); ctx.setFillColor(NSColor.white.cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(eye); ctx.clip()
    ctx.drawLinearGradient(gradient(NSColor(white: 0.80, alpha: 1), NSColor(white: 0.99, alpha: 1)),
                           start: CGPoint(x: 0, y: c.y + halfH), end: CGPoint(x: 0, y: c.y - halfH * 0.2), options: [.drawsAfterEndLocation])

    // Iris: the disk map — three rainbow rings, clipped by the lids.
    // Tiny sizes get one bold ring and no gaps: fine detail turns to mud at 16–32 px.
    let small = px <= 64
    let outer = side * (small ? 0.25 : 0.235), r0 = outer * (small ? 0.42 : 0.36)
    let rings: [[Double]] = small ? [[0.34, 0.22, 0.24, 0.20]]
        : [[0.42, 0.33, 0.25], [0.30, 0.12, 0.22, 0.10, 0.16], [0.18, 0.09, 0.07, 0.11, 0.09, 0.06, 0.12]]
    let ring = (outer - r0) / CGFloat(rings.count)
    let gap = small ? 0 : max(0.6, s / 512)
    // Dark iris base: where the outer rings stop short, the eye reads as depth, not a missing piece.
    ctx.setFillColor(NSColor(srgbRed: 0.10, green: 0.10, blue: 0.20, alpha: 1).cgColor)
    ctx.fillEllipse(in: CGRect(x: c.x - outer, y: c.y - outer, width: 2 * outer, height: 2 * outer))
    for (d, parts) in rings.enumerated() {
        var a = 0.0
        let fill = d == 0 ? 1.0 : 0.94 - 0.04 * Double(d)
        let total = parts.reduce(0, +) / fill
        for p in parts {
            let span = p / total * 2 * .pi
            let inner = r0 + CGFloat(d) * ring, outerR = inner + ring
            let path = CGMutablePath()
            path.addArc(center: c, radius: outerR, startAngle: .pi / 2 - a, endAngle: .pi / 2 - a - span, clockwise: true)
            path.addArc(center: c, radius: inner, startAngle: .pi / 2 - a - span, endAngle: .pi / 2 - a, clockwise: false)
            path.closeSubpath()
            ctx.addPath(path)
            ctx.setFillColor(NSColor(hue: (a + span / 2) / (2 * .pi), saturation: 0.66, brightness: 0.97 - 0.09 * Double(d), alpha: 1).cgColor)
            ctx.setStrokeColor(NSColor(srgbRed: 0.07, green: 0.07, blue: 0.14, alpha: 1).cgColor)
            ctx.setLineWidth(gap)
            ctx.drawPath(using: small ? .fill : .fillStroke)
            a += span
        }
    }
    // Limbal ring: a thin dark edge around the iris, as on a real eye.
    ctx.setStrokeColor(NSColor(srgbRed: 0.07, green: 0.07, blue: 0.14, alpha: 0.85).cgColor)
    ctx.setLineWidth(s * 0.008)
    ctx.strokeEllipse(in: CGRect(x: c.x - outer, y: c.y - outer, width: 2 * outer, height: 2 * outer))
    // Pupil and a glint.
    ctx.setFillColor(NSColor(srgbRed: 0.05, green: 0.05, blue: 0.10, alpha: 1).cgColor)
    ctx.fillEllipse(in: CGRect(x: c.x - r0, y: c.y - r0, width: 2 * r0, height: 2 * r0))
    let g = r0 * (small ? 0.55 : 0.42)
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
    ctx.fillEllipse(in: CGRect(x: c.x - r0 * 0.55 - g / 2, y: c.y + r0 * 0.25 - g / 2, width: g, height: g))
    ctx.restoreGState()

    // Lid line: a confident stroke along the upper lid, a lighter one below.
    let upper = CGMutablePath()
    upper.move(to: CGPoint(x: c.x - halfW, y: c.y))
    upper.addQuadCurve(to: CGPoint(x: c.x + halfW, y: c.y), control: CGPoint(x: c.x, y: c.y + halfH * 2))
    ctx.addPath(upper)
    ctx.setStrokeColor(NSColor(srgbRed: 0.04, green: 0.04, blue: 0.09, alpha: 1).cgColor)
    ctx.setLineWidth(s * 0.022); ctx.setLineCap(.round); ctx.strokePath()
    let lower = CGMutablePath()
    lower.move(to: CGPoint(x: c.x - halfW, y: c.y))
    lower.addQuadCurve(to: CGPoint(x: c.x + halfW, y: c.y), control: CGPoint(x: c.x, y: c.y - halfH * 2))
    ctx.addPath(lower)
    ctx.setStrokeColor(NSColor(srgbRed: 0.04, green: 0.04, blue: 0.09, alpha: 0.55).cgColor)
    ctx.setLineWidth(s * 0.010); ctx.strokePath()
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for base in [16, 32, 128, 256, 512] {
    try render(base).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try render(base * 2).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
if CommandLine.arguments.count > 2 {
    try render(1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
