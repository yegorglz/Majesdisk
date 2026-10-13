import CoreGraphics
import Foundation

public enum HitResult: Equatable { case center, segment(Int), none }

/// Inverse of the drawing math in a y-down view: a point at angle θ, radius r is (cx + r·sinθ, cy − r·cosθ).
public enum SunburstHitTest {
    public static func hit(point: CGPoint, center: CGPoint, outerRadius: Double, segments: [SunburstSegment], config: SunburstConfig) -> HitResult {
        let dx = Double(point.x - center.x), dy = Double(point.y - center.y)
        let r = (dx * dx + dy * dy).squareRoot()
        let r0 = config.centerRadius(outerRadius: outerRadius)
        if r <= r0 { return .center }
        if r > outerRadius { return .none }
        let depth = min(config.maxDepth, Int((r - r0) / config.ringWidth(outerRadius: outerRadius)) + 1)
        var theta = atan2(dx, -dy)
        if theta < 0 { theta += 2 * .pi }
        if let i = segments.firstIndex(where: { $0.depth == depth && $0.startAngle <= theta && theta < $0.endAngle }) {
            return .segment(i)
        }
        return .none
    }
}
