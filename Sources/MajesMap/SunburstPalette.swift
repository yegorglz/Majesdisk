import Foundation

public struct RGBA: Equatable, Sendable {
    public var r, g, b, a: Double
    public init(r: Double, g: Double, b: Double, a: Double) { self.r = r; self.g = g; self.b = b; self.a = a }

    public static func hsb(_ h: Double, _ s: Double, _ v: Double, alpha: Double = 1) -> RGBA {
        let h6 = (h - floor(h)) * 6, i = Int(h6) % 6, f = h6 - floor(h6)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        let (r, g, b): (Double, Double, Double)
        switch i {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }
        return RGBA(r: r, g: g, b: b, a: alpha)
    }
}

/// Rainbow hue around the circle for folders, grey files, purple restricted, translucent "smaller objects".
public enum SunburstPalette {
    public static func color(for s: SunburstSegment, highlighted: Bool) -> RGBA {
        let d = Double(s.depth - 1)
        var hue = 0.0, sat = 0.0, bri = 0.0, alpha = 1.0
        switch s.kind {
        case .directory, .package:
            (hue, sat, bri) = (s.midAngle / (2 * .pi), 0.62, max(0.45, 0.92 - 0.07 * d))
        case .smallerObjects:
            (hue, sat, bri, alpha) = (s.midAngle / (2 * .pi), 0.62, max(0.45, 0.92 - 0.07 * d), 0.35)
        case .file:
            bri = max(0.40, 0.72 - 0.04 * d)
        case .restricted:
            (hue, sat, bri) = (0.77, 0.45, 0.75)
        case .virtual:
            (bri, alpha) = (0.45, 0.6)
        }
        if highlighted { sat = max(0, sat - 0.1); bri = min(1, bri + 0.1) }
        return .hsb(hue, sat, bri, alpha: alpha)
    }
}
