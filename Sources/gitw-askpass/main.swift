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

            let client = AskpassClient()
            let resp = try client.request(socketPath: sock, nonce: nonce, prompt: prompt)
            // Git expects the response on stdout.
            print(resp)
            exit(0)
        } catch {
            exit(1)
        }
    }
}
