import Foundation

/// Apps can't request Full Disk Access; they can only detect it by touching a TCC-protected file.
public enum FullDiskAccess {
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    public static var defaultProbePaths: [String] {
        let home = NSHomeDirectory()
        return ["\(home)/Library/Application Support/com.apple.TCC/TCC.db",
                "/Library/Application Support/com.apple.TCC/TCC.db",
                "\(home)/Library/Safari/Bookmarks.plist"]
    }

    /// true = readable, false = the first existing probe is denied, nil = no probe exists.
    public static func isGranted(probePaths: [String] = defaultProbePaths) -> Bool? {
        for path in probePaths {
            let fd = open(path, O_RDONLY)
            if fd >= 0 { close(fd); return true }
            if errno == EPERM || errno == EACCES { return false }
        }
        return nil
    }
}
