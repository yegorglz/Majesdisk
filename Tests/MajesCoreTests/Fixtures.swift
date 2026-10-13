import Foundation

func makeTempDir() -> String {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("majes-\(UUID().uuidString)").path
    try! FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
    return (d as NSString).resolvingSymlinksInPath
}

func write(_ path: String, bytes: Int) {
    FileManager.default.createFile(atPath: path, contents: Data((0..<bytes).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }))
}

/// Physical size the way the kernel reports it.
func allocated(_ path: String) -> UInt64 {
    var st = stat()
    precondition(lstat(path, &st) == 0)
    return UInt64(st.st_blocks) * 512
}

func nfc(_ s: String) -> String { s.precomposedStringWithCanonicalMapping }
