import MajesCore
import SwiftUI

/// Local APFS snapshots on a volume; Time Machine ones can be deleted (as administrator).
struct SnapshotsSheet: View {
    let volume: VolumeInfo
    @Environment(\.dismiss) private var dismiss
    @State private var snapshots: [LocalSnapshot] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Local Snapshots on \(volume.name)").font(.title3.bold())
            if loading {
                ProgressView().frame(maxWidth: .infinity)
            } else if snapshots.isEmpty {
                Text("No local snapshots on this disk.").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 80)
            } else {
                List(snapshots) { s in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(s.name).lineLimit(1).truncationMode(.middle)
                            Text(s.isDeletable ? "Time Machine" : "Created by another app — delete it there")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if s.isDeletable { Button("Delete", role: .destructive) { delete(s) } }
                    }
                }
                .frame(minHeight: 160)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            Text("macOS removes Time Machine snapshots automatically after 24 hours.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20)
        .frame(width: 520)
        .task { await reload() }
    }

    func reload() async {
        loading = true
        let mount = volume.mountPath
        snapshots = await Task.detached { Snapshots.list(mountPath: mount) }.value
        loading = false
    }

    func delete(_ s: LocalSnapshot) {
        guard let cmd = Snapshots.deleteCommand(s) else { return }
        Task {
            do { _ = try await AdminRunner(prompt: "MajesDisk wants to delete a local snapshot.").run(cmd); error = nil }
            catch AdminRunnerError.cancelled {}
            catch { self.error = "\(error)" }
            await reload()
            AppModel.shared.refreshVolumes()
        }
    }
}
