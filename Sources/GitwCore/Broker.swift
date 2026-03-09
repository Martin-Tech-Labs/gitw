import Foundation
import Darwin

public struct BrokerConfig: Sendable {
    public let socketPath: String
    public let nonce: String
    public let timeoutSeconds: TimeInterval
    public let username: String
    public let token: String

    public init(socketPath: String, nonce: String, timeoutSeconds: TimeInterval, username: String, token: String) {
        self.socketPath = socketPath
        self.nonce = nonce
        self.timeoutSeconds = timeoutSeconds
        self.username = username
        self.token = token
    }
}

public final class AskpassBroker: @unchecked Sendable {
    private let cfg: BrokerConfig
    private let q = DispatchQueue(label: "gitw.broker")

    private var listenFD: Int32 = -1
    private var servedUsername = false
    private var servedToken = false
    private var isClosed = false

    public init(cfg: BrokerConfig) {
        self.cfg = cfg
    }

    public func start() throws {
        try q.sync {
            guard listenFD == -1 else { return }
            listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
            guard listenFD >= 0 else { throw GitwError.io("socket() failed") }

            // Best-effort cleanup if an old socket exists.
            _ = unlink(cfg.socketPath)

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
            guard cfg.socketPath.utf8.count < maxLen else {
                throw GitwError.io("socket path too long")
            }
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: maxLen) { cptr in
                    _ = memset(cptr, 0, maxLen)
                    _ = strncpy(cptr, cfg.socketPath, maxLen - 1)
                }
            }

            let len = socklen_t(MemoryLayout.size(ofValue: addr))
            let bres = withUnsafePointer(to: &addr) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                    bind(listenFD, sp, len)
                }
            }
            guard bres == 0 else {
                let e = errno
                throw GitwError.io("bind() failed: errno \(e)")
            }

            // Restrict socket file permissions.
            _ = chmod(cfg.socketPath, 0o600)

            guard listen(listenFD, 8) == 0 else {
                let e = errno
                throw GitwError.io("listen() failed: errno \(e)")
            }

            // Timeout.
            let t = DispatchSource.makeTimerSource(queue: q)
            t.schedule(deadline: .now() + cfg.timeoutSeconds)
            t.setEventHandler { [weak self] in
                self?.close()
            }
            t.resume()

            // Accept loop.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.acceptLoop()
            }
        }
    }

    public func close() {
        q.sync {
            guard !isClosed else { return }
            isClosed = true
            if listenFD >= 0 {
                _ = Darwin.close(listenFD)
                listenFD = -1
            }
            _ = unlink(cfg.socketPath)
        }
    }

    deinit {
        close()
    }

    private func acceptLoop() {
        while true {
            if q.sync(execute: { isClosed }) { return }

            var clientAddr = sockaddr_storage()
            var clientLen: socklen_t = socklen_t(MemoryLayout.size(ofValue: clientAddr))
            let fd = withUnsafeMutablePointer(to: &clientAddr) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                    accept(listenFD, sp, &clientLen)
                }
            }
            if fd < 0 {
                // If closed or interrupted, just exit.
                if errno == EBADF || errno == EINVAL { return }
                continue
            }

            handleClient(fd)
            _ = Darwin.close(fd)

            let done = q.sync { servedUsername && servedToken }
            if done {
                close()
                return
            }
        }
    }

    private func handleClient(_ fd: Int32) {
        func readLineFD() -> String? {
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

        guard let nonce = readLineFD(), nonce == cfg.nonce else {
            return
        }
        guard let prompt = readLineFD() else {
            return
        }

        let resp: String
        let lower = prompt.lowercased()
        if lower.contains("username") {
            resp = q.sync {
                if servedUsername { return "" }
                servedUsername = true
                return cfg.username
            }
        } else {
            resp = q.sync {
                if servedToken { return "" }
                servedToken = true
                return cfg.token
            }
        }

        _ = resp.withCString { cstr in
            Darwin.write(fd, cstr, strlen(cstr))
        }
        _ = "\n".withCString { cstr in
            Darwin.write(fd, cstr, 1)
        }
    }
}
