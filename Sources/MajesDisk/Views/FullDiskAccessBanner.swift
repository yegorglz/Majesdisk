import AppKit
import MajesCore
import SwiftUI

/// Shown on the overview until Full Disk Access is granted.
struct FullDiskAccessBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield").font(.title).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("MajesDisk can't see everything").font(.headline)
                Text("Grant Full Disk Access so protected folders (Mail, Messages, Safari, app containers) are measured instead of counted as hidden space. Then relaunch MajesDisk.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                FullDiskAccessButtons()
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
    }
}

struct FullDiskAccessButtons: View {
    var body: some View {
        HStack {
            Button("Open System Settings") { NSWorkspace.shared.open(FullDiskAccess.settingsURL) }
            Button("Reveal MajesDisk") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                .help("Drag the app into the Full Disk Access list if it isn't there")
            Button("Relaunch") { AppModel.relaunch() }
        }
    }
}
