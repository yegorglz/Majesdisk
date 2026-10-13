import MajesCore
import SwiftUI

/// Launch screen: every mounted volume with a live gauge, plus starred folders.
struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @State private var dropTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Disks").font(.title2.bold()).padding(.bottom, 4)
                ForEach(model.volumes) { v in
                    VolumeRowView(volume: v)
                    Divider()
                }
                HStack {
                    Text("Folders").font(.title2.bold())
                    Spacer()
                    Button("Scan Folder…") { model.chooseFolderAndScan() }
                }
                .padding(.top, 20)
                if model.starred.isEmpty {
                    Text("Drag a folder here to scan it. Star scanned folders to keep them in this list.")
                        .font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
                }
                ForEach(model.starred, id: \.self) { p in
                    FolderRowView(path: p)
                    Divider()
                }
            }
            .padding(24)
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: 3).padding(6)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.startScan(path: url.path, asAdministrator: false)
            return true
        } isTargeted: { dropTargeted = $0 }
        .navigationTitle("MajesDisk")
    }
}
