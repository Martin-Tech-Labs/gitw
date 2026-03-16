import Foundation
import Testing
@testable import GitwCore

struct AskpassClientTests {
    @Test
    func promptClassification() {
        #expect(AskpassRequestKind.fromGitPrompt("Username for 'https://github.com':") == .username)
        #expect(AskpassRequestKind.fromGitPrompt("Password for 'https://github.com':") == .token)
        #expect(AskpassRequestKind.fromGitPrompt("Something else") == nil)
    }

    @Test
    func requestLinesFormat() {
        let c = AskpassClient()
        #expect(c.makeRequestLines(nonce: "n", prompt: "p") == ["n", "p"])
    }

    @Test
    func requestWritesNonceThenPrompt() throws {
        var fds: [Int32] = [0, 0]
        pipe(&fds)
        let readFD = fds[0]
        let writeFD = fds[1]
        defer { _ = Darwin.close(readFD); _ = Darwin.close(writeFD) }

        let client = AskpassClient()
        client.writeRequest(fd: writeFD, nonce: "nonce", prompt: "prompt")

        var buf = [UInt8](repeating: 0, count: 64)
        let n = Darwin.read(readFD, &buf, buf.count)
        let s = String(bytes: buf.prefix(max(0, n)), encoding: .utf8) ?? ""
        #expect(s == "nonce\nprompt\n")
    }
}
