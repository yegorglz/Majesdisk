import Foundation
import Testing
@testable import MajesCore

@Test func passesArgumentsWithoutShellInjection() async throws {
    let marker = "/tmp/pwned-\(UUID())"
    let evil = #"it's "q" $HOME; touch "# + marker
    let out = try await AdminRunner(administrator: false).run(["/bin/echo", evil])
    #expect(out == evil)
    #expect(!FileManager.default.fileExists(atPath: marker))
}

@Test func reportsFailureStatus() async {
    await #expect(throws: AdminRunnerError.self) { try await AdminRunner(administrator: false).run(["/usr/bin/false"]) }
}

@Test func adminScriptQuotesPrompt() {
    let args = AdminRunner.osascriptArguments(command: ["/bin/ls"], administrator: true, prompt: #"say "hi" \ there"#)
    #expect(args.contains(#"return do shell script cmd with prompt "say \"hi\" \\ there" with administrator privileges"#))
    #expect(args.last == "/bin/ls")
}
