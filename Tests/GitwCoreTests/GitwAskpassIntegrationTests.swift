import Foundation
import Testing
@testable import GitwCore

struct GitwAskpassIntegrationTests {
    @Test
    func askpassExecutableTalksToBroker() throws {
        // Integration-ish test (A): start a real broker on a real UDS,
        // then run the built gitw-askpass executable and ensure it prints the broker response.

        let tmpDir = URL(fileURLWithPath: "/tmp").appendingPathComponent("gitw-it-\(String(UUID().uuidString.prefix(8)))")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: false,
                                                attributes: [FileAttributeKey.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let sock = tmpDir.appendingPathComponent("askpass.sock").path

        let cfg = BrokerConfig(socketPath: sock,
                               nonce: "n",
                               timeoutSeconds: 2,
                               username: "the-user",
                               token: "the-token")
        let broker = AskpassBroker(cfg: cfg)
        try broker.start()
        defer { broker.close() }

        // Wait briefly for the socket to appear.
        for _ in 0..<50 {
            if FileManager.default.fileExists(atPath: sock) { break }
            usleep(5_000)
        }

        let exe = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/gitw-askpass").path

        // 1) Username prompt
        let p1 = Process()
        p1.executableURL = URL(fileURLWithPath: exe)
        p1.arguments = ["Username for https://github.com"]
        p1.environment = ["GITW_SOCKET": sock, "GITW_NONCE": "n"]
        let out1 = Pipe()
        p1.standardOutput = out1
        p1.standardError = Pipe()
        try p1.run()
        p1.waitUntilExit()
        let s1 = String(data: out1.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(s1.trimmingCharacters(in: .whitespacesAndNewlines) == "the-user")

        // 2) Token prompt
        let p2 = Process()
        p2.executableURL = URL(fileURLWithPath: exe)
        p2.arguments = ["Password for https://github.com"]
        p2.environment = ["GITW_SOCKET": sock, "GITW_NONCE": "n"]
        let out2 = Pipe()
        p2.standardOutput = out2
        p2.standardError = Pipe()
        try p2.run()
        p2.waitUntilExit()
        let s2 = String(data: out2.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(s2.trimmingCharacters(in: .whitespacesAndNewlines) == "the-token")
    }
}
