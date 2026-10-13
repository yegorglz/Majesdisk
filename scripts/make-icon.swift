// Renders the MajesDisk app icon (a small sunburst) into an .iconset folder.
// Usage: swift scripts/make-icon.swift <out.iconset>
import AppKit

let out = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px), inset = s * 0.09
    let bg = CGPath(roundedRect: CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset),
                    cornerWidth: s * 0.2, cornerHeight: s * 0.2, transform: nil)
    ctx.addPath(bg); ctx.setFillColor(NSColor(white: 0.13, alpha: 1).cgColor); ctx.fillPath()
    let c = CGPoint(x: s / 2, y: s / 2), outer = s * 0.36, r0 = outer * 0.3
    let ring = (outer - r0) / 3
    let rings: [[Double]] = [[0.45, 0.3, 0.25], [0.3, 0.12, 0.2, 0.1, 0.15], [0.2, 0.1, 0.08, 0.12, 0.1, 0.05]]
    for (d, parts) in rings.enumerated() {
        var a = 0.0
        let total = parts.reduce(0, +) * (d == 0 ? 1 : 1.0 / 0.87)
        for p in parts {
            let span = p / total * 2 * .pi
            let inner = r0 + CGFloat(d) * ring, outerR = inner + ring
            let path = CGMutablePath()
            path.addArc(center: c, radius: outerR, startAngle: .pi / 2 - a, endAngle: .pi / 2 - a - span, clockwise: true)
            path.addArc(center: c, radius: inner, startAngle: .pi / 2 - a - span, endAngle: .pi / 2 - a, clockwise: false)
            path.closeSubpath()
            ctx.addPath(path)
            ctx.setFillColor(NSColor(hue: (a + span / 2) / (2 * .pi), saturation: 0.62, brightness: 0.95 - 0.08 * Double(d), alpha: 1).cgColor)
            ctx.setStrokeColor(NSColor(white: 0.13, alpha: 1).cgColor)
            ctx.setLineWidth(max(1, s / 256))
            ctx.drawPath(using: .fillStroke)
            a += span
        }
    }
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: c.x - r0 * 0.8, y: c.y - r0 * 0.8, width: r0 * 1.6, height: r0 * 1.6))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
