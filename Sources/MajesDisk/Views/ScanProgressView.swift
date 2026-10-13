import MajesCore
import SwiftUI

/// Scanning screen: a slowly turning flower, live counts and the current folder.
struct ScanProgressView: View {
    let session: ScanSession

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            TimelineView(.animation) { context in
                Canvas { ctx, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    let t = context.date.timeIntervalSinceReferenceDate
                    for i in 0..<12 {
                        let a = Double(i) / 12 * 2 * .pi + t * 0.8
                        var petal = Path(ellipseIn: CGRect(x: -14, y: -size.height * 0.46, width: 28, height: size.height * 0.36))
                        petal = petal.applying(CGAffineTransform(rotationAngle: a)).applying(CGAffineTransform(translationX: c.x, y: c.y))
                        ctx.fill(petal, with: .color(Color(hue: Double(i) / 12, saturation: 0.6, brightness: 0.9).opacity(0.85)))
                    }
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 18, y: c.y - 18, width: 36, height: 36)), with: .color(.white))
                }
            }
            .frame(width: 160, height: 160)
            Text(session.asAdministrator ? "Scanning \(name) as administrator…" : "Scanning \(name)…").font(.title2.bold())
            Text("\(session.progress.files.formatted()) files · \(ByteFormat.string(session.progress.bytes))")
                .font(.headline).monospacedDigit().foregroundStyle(.secondary)
            Text(session.progress.currentPath)
                .font(.caption.monospaced()).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: 600)
            Button("Stop") { session.cancel() }.keyboardShortcut(.cancelAction)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var name: String { session.volume?.name ?? (session.rootPath as NSString).lastPathComponent }
}
