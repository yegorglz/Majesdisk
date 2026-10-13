import Foundation

public struct LocalSnapshot: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    /// "YYYY-MM-DD-HHMMSS" for Time Machine snapshots; nil for other apps' snapshots.
    public var timeMachineDate: String?
    public var isDeletable: Bool { timeMachineDate != nil }
}

/// Local APFS snapshots via `tmutil`. Deleting and purging need root (run through AdminRunner).
public enum Snapshots {
    public static func parse(_ output: String) -> [LocalSnapshot] {
        output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("Snapshots for") }
            .map { name in
                LocalSnapshot(name: name, timeMachineDate: name.firstMatch(of: #/^com\.apple\.TimeMachine\.(\d{4}-\d{2}-\d{2}-\d{6})\.local$/#).map { String($0.1) })
            }
    }

    public static func list(mountPath: String) -> [LocalSnapshot] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        p.arguments = ["listlocalsnapshots", mountPath]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return parse(String(decoding: data, as: UTF8.self))
    }

    public static func deleteCommand(_ s: LocalSnapshot) -> [String]? {
        s.timeMachineDate.map { ["/usr/bin/tmutil", "deletelocalsnapshots", $0] }
    }

    /// Asks macOS to reclaim as much purgeable space as it can, at the highest urgency.
    public static func purgeCommand(mountPath: String) -> [String] {
        ["/usr/bin/tmutil", "thinlocalsnapshots", mountPath, "999999999999999", "4"]
    }
}
