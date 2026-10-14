import MajesCore
import SwiftUI

/// A small ring that echoes the map: filled share of the disk, green while at least half is free,
/// then orange, then red. Percent used in the middle.
struct GaugeView: View {
    let fraction: Double
    var lineWidth: CGFloat = 6
    /// Fixed color (scan progress); nil = disk-fullness colors.
    var tint: Color? = nil

    var color: Color {
        if let tint { return tint }
        switch GaugeLevel.forFraction(fraction) {
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, fraction)))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(fraction, format: .percent.precision(.fractionLength(0)))
                .font(.system(.caption, design: .rounded).weight(.semibold)).monospacedDigit()
        }
        .animation(.easeInOut(duration: 0.4), value: fraction)
        .accessibilityElement()
        .accessibilityLabel("\(Int(fraction * 100)) percent full")
    }
}
