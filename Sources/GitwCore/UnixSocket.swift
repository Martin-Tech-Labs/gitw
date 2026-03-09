import Foundation
import Darwin

public enum UnixSocket {
    public static func connect(path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw GitwError.io("socket() failed") }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < maxLen else { throw GitwError.io("socket path too long") }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: maxLen) { cptr in
                _ = memset(cptr, 0, maxLen)
                _ = strncpy(cptr, path, maxLen - 1)
            }
        }

        let len = socklen_t(MemoryLayout.size(ofValue: addr))
        let res = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                Darwin.connect(fd, sp, len)
            }
        }
        guard res == 0 else {
            let e = errno
            _ = Darwin.close(fd)
            throw GitwError.io("connect() failed: errno \(e)")
        }
        return fd
    }

    public static func readAll(fd: Int32, maxBytes: Int = 64 * 1024) -> Data {
        var out = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while out.count < maxBytes {
            let n = Darwin.read(fd, &buf, buf.count)
            if n <= 0 { break }
            out.append(buf, count: n)
        }
        return out
    }
}
