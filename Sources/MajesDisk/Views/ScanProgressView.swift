import SwiftUI

struct ScanProgressView: View {
    let session: ScanSession
    var body: some View { Button("Stop") { session.cancel() } }
}
