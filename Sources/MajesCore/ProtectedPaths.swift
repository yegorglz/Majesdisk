import Foundation

public enum ProtectionVerdict: Equatable, Sendable { case allowed, protected(String) }

/// Folders MajesDisk refuses to collect or delete, whatever the UI lets through.
public enum ProtectedPaths {
    static let essential = "This folder is essential to macOS or your account."
    static let system = "This item is protected by macOS."
    static let exact: Set<String> = [
        "/", "/System", "/Library", "/Applications", "/Users", "/usr", "/bin", "/sbin", "/private", "/private/var",
        "/private/etc", "/private/tmp", "/var", "/etc", "/tmp", "/opt", "/cores", "/dev", "/Volumes",
    ]
    static let homeChildren = ["Library", "Desktop", "Documents", "Downloads", "Pictures", "Music", "Movies"]
    static let prefixes = ["/System/", "/bin/", "/sbin/", "/private/var/db/", "/var/db/", "/dev/"]

    public static func verdict(for path: String, homeDirectory: String = NSHomeDirectory(), volumeRoots: [String] = []) -> ProtectionVerdict {
        let p = normalize(path), home = normalize(homeDirectory)
        let isAccountHome = p.hasPrefix("/Users/") && p.split(separator: "/").count == 2  // any user's home, /Users/Shared
        if exact.contains(p) || p == home || isAccountHome || homeChildren.contains(where: { p == home + "/" + $0 })
            || volumeRoots.map(normalize).contains(p) {
            return .protected(essential)
        }
        if prefixes.contains(where: { p.hasPrefix($0) }) || (p.hasPrefix("/usr/") && !p.hasPrefix("/usr/local/")) {
            return .protected(system)
        }
        if home.hasPrefix(p + "/") { return .protected(essential) }
        return .allowed
    }

    /// Absolute path with ".", "..", empty parts and trailing slash removed; symlinks are not resolved.
    static func normalize(_ path: String) -> String {
        var parts: [Substring] = []
        for c in path.split(separator: "/") {
            if c == "." { continue }
            if c == ".." { _ = parts.popLast(); continue }
            parts.append(c)
        }
        return "/" + parts.joined(separator: "/")
    }
}
