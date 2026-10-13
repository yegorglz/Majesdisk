import AppKit
import MajesCore
import SwiftUI

struct VolumeRowView: View {
    @Environment(AppModel.self) private var model
    let volume: VolumeInfo

    var body: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: volume.mountPath))
                .resizable().frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(volume.name).font(.headline)
                Text("\(volume.fileSystem) · \(ByteFormat.string(volume.totalBytes))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 220, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                GaugeView(fraction: volume.usedFraction(purgeableAsUsed: model.optionKeyDown))
                Text(model.optionKeyDown
                     ? "\(ByteFormat.string(volume.availableBytes)) free (\(ByteFormat.string(volume.purgeableBytes)) purgeable)"
                     : "\(ByteFormat.string(volume.freeBytes)) free")
                    .font(.caption).foregroundStyle(.secondary)
                    .help("\(ByteFormat.string(volume.usedBytes)) used")
            }
            Spacer(minLength: 12)
            Menu {
                Button("Scan") { model.startScan(path: volume.mountPath, asAdministrator: false) }
                Button("Scan as Administrator") { model.startScan(path: volume.mountPath, asAdministrator: true) }
                Divider()
                Button("Local Snapshots…") { model.showSnapshots(for: volume) }
            } label: {
                Text("Scan")
            } primaryAction: {
                model.startScan(path: volume.mountPath, asAdministrator: false)
            }
            .menuStyle(.borderedButton)
            .fixedSize()
        }
        .padding(.vertical, 8)
    }
}

struct FolderRowView: View {
    @Environment(AppModel.self) private var model
    let path: String

    var body: some View {
        HStack(spacing: 16) {
            Button { model.toggleStar(path) } label: {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 40, height: 40)
                    Image(systemName: model.starred.contains(path) ? "star.fill" : "star")
                        .foregroundStyle(.yellow).font(.caption)
                }
            }
            .buttonStyle(.plain)
            .help(model.starred.contains(path) ? "Unstar this folder" : "Star this folder to keep it here")
            VStack(alignment: .leading, spacing: 2) {
                Text((path as NSString).lastPathComponent).font(.headline)
                Text(path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button("Scan") { model.startScan(path: path, asAdministrator: false) }
        }
        .padding(.vertical, 6)
    }
}
