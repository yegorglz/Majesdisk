import Foundation
import Testing
@testable import MajesCore

@Test func fdaProbeSemantics() {
    let d = makeTempDir()
    write("\(d)/ok", bytes: 1)
    write("\(d)/locked", bytes: 1); chmod("\(d)/locked", 0o000)
    defer { chmod("\(d)/locked", 0o644) }
    #expect(FullDiskAccess.isGranted(probePaths: ["\(d)/ok"]) == true)
    if getuid() != 0 { #expect(FullDiskAccess.isGranted(probePaths: ["\(d)/locked"]) == false) }
    #expect(FullDiskAccess.isGranted(probePaths: ["\(d)/missing"]) == nil)
    #expect(FullDiskAccess.isGranted(probePaths: ["\(d)/missing", "\(d)/ok"]) == true)
    #expect(FullDiskAccess.settingsURL.absoluteString.contains("Privacy_AllFiles"))
}
