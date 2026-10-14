import Foundation
import Testing
@testable import MajesCore

@Test func protectedPathRules() {
    let h = "/Users/me"
    for p in ["/", "/System", "/System/Library/Fonts", "/Library", "/Applications", "/Users", h, "\(h)/Library",
              "\(h)/Desktop", "\(h)/Documents", "\(h)/Downloads", "/usr/bin", "/private/var", "/private/var/db/x", "/Volumes",
              "/Volumes/Ext", "/dev", "/bin/ls", "/usr", "/Users/anna", "/Users/Shared", "/Users/anna/"] {
        #expect(ProtectedPaths.verdict(for: p, homeDirectory: h, volumeRoots: ["/Volumes/Ext"]) != .allowed, "\(p)")
    }
    for p in ["/Applications/Foo.app", "\(h)/Library/Caches", "\(h)/Downloads/big.dmg", "/usr/local/lib", "/Volumes/Ext/movie.mov",
              "/Library/Caches/x", "/Users/other/file"] {
        #expect(ProtectedPaths.verdict(for: p, homeDirectory: h, volumeRoots: ["/Volumes/Ext"]) == .allowed, "\(p)")
    }
    #expect(ProtectedPaths.verdict(for: "\(h)/", homeDirectory: h) != .allowed)
    #expect(ProtectedPaths.verdict(for: "\(h)/Library/../Library", homeDirectory: h) != .allowed)
}
