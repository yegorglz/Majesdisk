import Foundation
import Testing
@testable import MajesCore

@Test func helperScanWritesDecodableTree() throws {
    let d = makeTempDir(); write("\(d)/a", bytes: 9_000); write("\(d)/b", bytes: 20_000)
    let w = makeTempDir()
    let rc = HelperCommand.run(arguments: ["scan", "--root", d, "--out", "\(w)/o", "--progress", "\(w)/p", "--cancel", "\(w)/c"])
    #expect(rc == 0)
    let t = try TreeCodec.decode(Data(contentsOf: URL(fileURLWithPath: "\(w)/o")))
    #expect(t.size(t.root) == allocated("\(d)/a") + allocated("\(d)/b"))
    let p = try JSONDecoder().decode(HelperProgress.self, from: Data(contentsOf: URL(fileURLWithPath: "\(w)/p")))
    #expect(p.files == 2)
}

@Test func helperScanHonorsCancelFile() {
    let d = makeTempDir(); let w = makeTempDir()
    FileManager.default.createFile(atPath: "\(w)/c", contents: nil)
    #expect(HelperCommand.run(arguments: ["scan", "--root", d, "--out", "\(w)/o", "--progress", "\(w)/p", "--cancel", "\(w)/c"]) == 3)
    #expect(!FileManager.default.fileExists(atPath: "\(w)/o"))
}

@Test func helperRejectsUnknownCommand() {
    #expect(HelperCommand.run(arguments: ["bogus"]) == 2)
    #expect(HelperCommand.run(arguments: ["scan", "--root"]) == 2)
}

@Test func helperDeleteRefusesProtected() {
    let d = makeTempDir(); write("\(d)/f", bytes: 10)
    let pipe = Pipe()
    let saved = dup(STDOUT_FILENO)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
    let rc = HelperCommand.run(arguments: ["delete", "--home", "/Users/me", "/Users/me", "\(d)/f"])
    fflush(stdout); dup2(saved, STDOUT_FILENO); close(saved)
    try? pipe.fileHandleForWriting.close()
    let lines = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n")
    #expect(rc == 0)
    #expect(!FileManager.default.fileExists(atPath: "\(d)/f"))
    let results = lines.compactMap { try? JSONDecoder().decode(HelperDeleteResult.self, from: Data($0.utf8)) }
    #expect(results.first { $0.path == "/Users/me" }?.error == "protected")
    #expect(results.first { $0.path == "\(d)/f" }?.error == nil)
}
