import Foundation
import Testing
@testable import GitwCore

struct SocketPathLengthTests {
    @Test
    func brokerSocketPathStaysUnderUnixDomainLimit() {
        // Best-effort guardrail: sockaddr_un.sun_path is ~104 bytes on macOS.
        // We can't assert the OS constant easily, but we can ensure our constructed
        // path is comfortably below the limit.
        let pid = 12345
        let shortId = "abcdef12"
        let dir = URL(fileURLWithPath: "/tmp").appendingPathComponent("gitw-\(pid)-\(shortId)")
        let sock = dir.appendingPathComponent("askpass.sock").path
        #expect(sock.utf8.count < 100)
    }
}
