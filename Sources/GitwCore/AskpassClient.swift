import Foundation

public enum AskpassRequestKind: Equatable {
    case username
    case token

    public static func fromGitPrompt(_ prompt: String) -> AskpassRequestKind? {
        // Git typically asks:
        //  - "Username for 'https://github.com':"
        //  - "Password for 'https://github.com':"
        // but we keep it loose and case-insensitive.
        let p = prompt.lowercased()
        if p.contains("username") { return .username }
        if p.contains("password") { return .token }
        return nil
    }
}

public struct AskpassClient {
    public init() {}

    /// Format the on-wire request lines sent to the broker.
    /// Protocol:
    ///   <nonce>\n
    ///   <prompt>\n
    public func makeRequestLines(nonce: String, prompt: String) -> [String] {
        [nonce, prompt]
    }

    public func writeRequest(fd: Int32, nonce: String, prompt: String, writeFn: (Int32, UnsafeRawPointer, Int) -> Int = Darwin.write) {
        for line in makeRequestLines(nonce: nonce, prompt: prompt) {
            let s = line + "\n"
            s.utf8CString.withUnsafeBytes { buf in
                _ = writeFn(fd, buf.baseAddress!, buf.count - 1)
            }
        }
    }

    public func readResponse(fd: Int32, readAll: (Int32, Int) -> Data = UnixSocket.readAll(fd:maxBytes:)) throws -> String {
        let data = readAll(fd, 4096)
        guard let s = String(data: data, encoding: .utf8) else {
            throw GitwError.io("askpass: invalid utf8 from broker")
        }
        return s.trimmingCharacters(in: .newlines)
    }

    /// High-level helper used by `gitw-askpass`.
    public func request(socketPath: String,
                        nonce: String,
                        prompt: String,
                        connect: (String) throws -> Int32 = UnixSocket.connect(path:)) throws -> String {
        let fd = try connect(socketPath)
        defer { _ = Darwin.close(fd) }
        writeRequest(fd: fd, nonce: nonce, prompt: prompt)
        return try readResponse(fd: fd)
    }
}
