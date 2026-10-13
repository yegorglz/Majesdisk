import MajesCore
import SwiftUI

struct SettingsView: View {
    @AppStorage("deleteMode") private var deleteMode = DeleteMode.permanent.rawValue
    @State private var fda = FullDiskAccess.isGranted()

    var body: some View {
        TabView {
            Form {
                Picker("When deleting:", selection: $deleteMode) {
                    Text("Delete immediately (frees space now)").tag(DeleteMode.permanent.rawValue)
                    Text("Move to Trash").tag(DeleteMode.moveToTrash.rawValue)
                }
                .pickerStyle(.radioGroup)
                Text("Delete waits 5 seconds so you can cancel. Deleted items can't be recovered from the Trash.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            .tabItem { Label("General", systemImage: "gearshape") }

            VStack(alignment: .leading, spacing: 12) {
                Label(fda == true ? "Full Disk Access is granted." : "Full Disk Access is not granted.",
                      systemImage: fda == true ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(fda == true ? .green : .orange).font(.headline)
                Text("""
                1. Open System Settings › Privacy & Security › Full Disk Access.
                2. Turn on MajesDisk (or click + and choose it).
                3. Relaunch MajesDisk, then rescan.
                """)
                FullDiskAccessButtons()
                Text("Development builds signed ad hoc get a new identity on every rebuild; grant access again after rebuilding, or sign with MAJESDISK_SIGN_IDENTITY.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in fda = FullDiskAccess.isGranted() }
            .tabItem { Label("Full Disk Access", systemImage: "lock.shield") }

            VStack(alignment: .leading, spacing: 10) {
                Text("Scan as Administrator").font(.headline)
                Text("""
                Choose “Scan as Administrator” from a disk's Scan menu to measure folders your account can't read, such as other users' homes and root-only system data. macOS asks for an administrator password each time; nothing stays installed.

                If some protected folders still read as empty during an administrator scan, also add MajesDisk.app/Contents/Helpers/majes-helper to the Full Disk Access list.

                When an item can't be deleted for lack of permission, MajesDisk offers “Delete as Administrator”.
                """)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .tabItem { Label("Administrator", systemImage: "person.badge.key") }
        }
        .frame(width: 520, height: 300)
    }
}
