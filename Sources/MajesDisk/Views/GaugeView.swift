import MajesCore
import SwiftUI

/// Horizontal fill gauge: green while at least half is free, then orange, then red.
struct GaugeView: View {
    let fraction: Double

    var color: Color {
        switch GaugeLevel.forFraction(fraction) {
        case .green: .green
        case .orange: .orange
        case .red: .red
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(color.gradient).frame(width: max(6, geo.size.width * min(1, fraction)))
            }
        }
        .frame(height: 8)
        .animation(.easeInOut(duration: 0.3), value: fraction)
        .accessibilityElement()
        .accessibilityLabel("\(Int(fraction * 100)) percent full")
    }
}
