import Foundation
import Darwin
import Testing
@testable import GitwCore

struct AskpassBrokerTests {
    private func withTempSocketPath(_ fn: (String) throws -> Void) throws {
        // Use /tmp to keep Unix domain socket paths short enough for sockaddr_un.
        let dir = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("gitw-t-\(String(UUID().uuidString.prefix(8)))")
        try FileManager.default.createDirectory(at: dir,
                                                withIntermediateDirectories: false,
                                                attributes: [FileAttributeKey.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: dir) }
        try fn(dir.appendingPathComponent("askpass.sock").path)
    }

    private func readLineWithTimeout(fd: Int32, timeoutMs: Int) -> String? {
        var tv = timeval(tv_sec: timeoutMs / 1000, tv_usec: __darwin_suseconds_t((timeoutMs % 1000) * 1000))
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout.size(ofValue: tv)))

        var buf = [UInt8]()
        buf.reserveCapacity(256)
        var byte: UInt8 = 0
        while true {
            let n = Darwin.read(fd, &byte, 1)
            if n <= 0 { return nil }
            if byte == 0x0A { break }
            buf.append(byte)
            if buf.count > 16_384 { return nil }
        }
        return String(bytes: buf, encoding: .utf8)
    }

    private func sendRequest(socketPath: String, nonce: String, prompt: String) throws -> String? {
        // The socket file is created by bind(); on some systems this can take a moment to appear.
        for _ in 0..<50 {
            if FileManager.default.fileExists(atPath: socketPath) { break }
            usleep(5_000) // 5ms
        }

        let fd = try UnixSocket.connect(path: socketPath)
        defer { _ = Darwin.close(fd) }

        func writeLine(_ s: String) {
            let line = s + "\n"
            _ = line.withCString { cstr in
                Darwin.write(fd, cstr, strlen(cstr))
            }
        }

        writeLine(nonce)
        writeLine(prompt)

        return readLineWithTimeout(fd: fd, timeoutMs: 250)
    }

    @Test
    func brokerRequiresNonce() throws {
        try withTempSocketPath { sock in
            let cfg = BrokerConfig(socketPath: sock,
                                   nonce: "good-nonce",
                                   timeoutSeconds: 2,
                                   username: "u",
                                   token: "t")
            let broker = AskpassBroker(cfg: cfg)
            try broker.start()
            defer { broker.close() }

            let resp = try sendRequest(socketPath: sock, nonce: "bad-nonce", prompt: "Username for https://github.com")
            #expect(resp == nil, "Broker should not respond if nonce is wrong")
        }
    }

    @Test
    func brokerServesUsernameThenTokenOnce() throws {
        try withTempSocketPath { sock in
            let cfg = BrokerConfig(socketPath: sock,
                                   nonce: "n",
                                   timeoutSeconds: 2,
                                   username: "the-user",
                                   token: "the-token")
            let broker = AskpassBroker(cfg: cfg)
            try broker.start()
            defer { broker.close() }

            let u1 = try sendRequest(socketPath: sock, nonce: "n", prompt: "Username for https://github.com")
            #expect(u1 == "the-user")

            let t1 = try sendRequest(socketPath: sock, nonce: "n", prompt: "Password for https://github.com")
            #expect(t1 == "the-token")

            // After both secrets are served once, the broker closes and removes the socket.
            // Further connections should fail (fail closed).
            for _ in 0..<50 {
                if !FileManager.default.fileExists(atPath: sock) { break }
                usleep(5_000)
            }
            #expect(!FileManager.default.fileExists(atPath: sock))

            do {
                _ = try sendRequest(socketPath: sock, nonce: "n", prompt: "Username for https://github.com")
                Issue.record("Expected connect to fail after broker closed")
            } catch {
                // expected
            }
        }
    }
}
