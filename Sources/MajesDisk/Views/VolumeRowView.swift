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
                ScannedLabel(path: volume.mountPath)
            }
            .frame(width: 220, alignment: .leading)
            Spacer(minLength: 12)
            GaugeView(fraction: volume.usedFraction(purgeableAsUsed: model.optionKeyDown)).frame(width: 46, height: 46)
            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteFormat.string(model.optionKeyDown ? volume.availableBytes : volume.freeBytes))
                    .font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
                Text(model.optionKeyDown ? "free, \(ByteFormat.string(volume.purgeableBytes)) purgeable counted as used" : "free")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(minWidth: 120, alignment: .trailing)
            .help("\(ByteFormat.string(volume.usedBytes)) used of \(ByteFormat.string(volume.totalBytes))")
            ScanMenuButton(path: volume.mountPath, volume: volume)
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
                ScannedLabel(path: path)
            }
            Spacer()
            ScanMenuButton(path: path, volume: nil)
        }
        .padding(.vertical, 6)
    }
}

/// DaisyDisk's split button: "Scan" before a scan, "Show" once results exist (kept until forgotten).
struct ScanMenuButton: View {
    @Environment(AppModel.self) private var model
    let path: String
    let volume: VolumeInfo?

    var body: some View {
        let cached = model.hasResults(path)
        if model.loadingPath == path {
            ProgressView().controlSize(.small).frame(width: 70)
        } else {
        Menu {
            if cached {
                Button("Show") { model.showResults(for: path) }
                Button("Rescan") { model.startScan(path: path, asAdministrator: false) }
                Button("Rescan as Administrator") { model.startScan(path: path, asAdministrator: true) }
                Button("Forget Scan Results") { model.forget(path: path) }
            } else {
                Button("Scan") { model.startScan(path: path, asAdministrator: false) }
                Button("Scan as Administrator") { model.startScan(path: path, asAdministrator: true) }
            }
            if let volume {
                Divider()
                Button("Local Snapshots…") { model.showSnapshots(for: volume) }
            }
        } label: {
            Text(cached ? "Show" : "Scan")
        } primaryAction: {
            cached ? model.showResults(for: path) : model.startScan(path: path, asAdministrator: false)
        }
        .menuStyle(.borderedButton)
        .fixedSize()
        }
    }
}

/// "Scanned 3 days ago" under a disk or folder that has saved results.
struct ScannedLabel: View {
    @Environment(AppModel.self) private var model
    let path: String

    var body: some View {
        if let date = model.savedScans[path] {
            Text("Scanned \(date.formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
