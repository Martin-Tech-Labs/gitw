import Foundation
import GitwCore

@main
struct GitwAskpass {
    static func main() {
        do {
            let env = ProcessInfo.processInfo.environment
            guard let sock = env["GITW_SOCKET"], !sock.isEmpty else {
                // Fail closed.
                exit(1)
            }
            guard let nonce = env["GITW_NONCE"], !nonce.isEmpty else {
                exit(1)
            }

            let prompt = CommandLine.arguments.dropFirst().joined(separator: " ")

            let fd = try UnixSocket.connect(path: sock)
            defer { _ = Darwin.close(fd) }

            func writeLine(_ s: String) {
                let line = s + "\n"
                _ = line.withCString { cstr in
                    Darwin.write(fd, cstr, strlen(cstr))
                }
            }

            writeLine(nonce)
            writeLine(prompt)

            let data = UnixSocket.readAll(fd: fd, maxBytes: 4096)
            if let s = String(data: data, encoding: .utf8) {
                // Git expects the response on stdout.
                print(s.trimmingCharacters(in: .newlines))
                exit(0)
            }
            exit(1)
        } catch {
            exit(1)
        }
    }
}
