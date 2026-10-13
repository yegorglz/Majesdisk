import Foundation

public enum AdminRunnerError: Error, Equatable { case cancelled, failed(status: Int32, message: String) }

/// Runs one command as root through the standard macOS administrator password prompt.
/// Arguments travel as AppleScript `argv` and are shell-quoted there, never interpolated.
public struct AdminRunner: Sendable {
    public var administrator: Bool
    public var prompt: String

    public init(administrator: Bool = true, prompt: String = "MajesDisk needs administrator access.") {
        self.administrator = administrator; self.prompt = prompt
    }

    public static func osascriptArguments(command: [String], administrator: Bool, prompt: String) -> [String] {
        ["-e", "on run argv",
         "-e", "set cmd to \"\"",
         "-e", "repeat with a in argv",
         "-e", "set cmd to cmd & quoted form of (a as text) & \" \"",
         "-e", "end repeat",
         "-e", administrator ? "return do shell script cmd with prompt \(appleScriptLiteral(prompt)) with administrator privileges"
                             : "return do shell script cmd",
         "-e", "end run"] + command
    }

    static func appleScriptLiteral(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Returns the command's stdout. Throws `.cancelled` when the user dismisses the password prompt.
    public func run(_ command: [String]) async throws -> String {
        let args = Self.osascriptArguments(command: command, administrator: administrator, prompt: prompt)
        return try await Task.detached(priority: .userInitiated) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = args
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            try p.run()
            var errData = Data()
            let errReader = Thread { errData = err.fileHandleForReading.readDataToEndOfFile() }
            errReader.start()
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            while !errReader.isFinished { usleep(1000) }
            let stdout = String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .newlines)
            let stderr = String(decoding: errData, as: UTF8.self)
            if p.terminationStatus == 0 { return stdout }
            if stderr.contains("(-128)") { throw AdminRunnerError.cancelled }
            throw AdminRunnerError.failed(status: p.terminationStatus, message: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }.value
    }
}
