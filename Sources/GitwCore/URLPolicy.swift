import Foundation

public enum URLPolicy {
    public static func validateGitArguments(_ args: [String]) throws {
        // Deny obvious bypasses.
        var i = 0
        while i < args.count {
            let a = args[i]
            if a == "-c" {
                if i + 1 < args.count {
                    let kv = args[i + 1]
                    let lowered = kv.lowercased()
                    if lowered.hasPrefix("credential.") || lowered.hasPrefix("core.askpass") || lowered.hasPrefix("core.sshcommand") {
                        throw GitwError.denied("refusing to run git with '-c \(kv)'")
                    }
                }
                i += 2
                continue
            }
            i += 1
        }

        for a in args {
            if a.hasPrefix("git@") {
                throw GitwError.denied("SSH-style Git URLs are not allowed (use https://github.com/…)")
            }
            if a.hasPrefix("ssh://") || a.hasPrefix("git://") || a.hasPrefix("http://") {
                throw GitwError.denied("Only https://github.com/… remotes are allowed")
            }
            if a.contains("://") {
                guard let url = URL(string: a), let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
                    continue
                }
                if scheme != "https" {
                    throw GitwError.denied("Only https remotes are allowed (got \(scheme))")
                }
                if host != "github.com" {
                    throw GitwError.denied("Only github.com remotes are allowed (got \(host))")
                }
                if (url.user != nil) || (url.password != nil) {
                    throw GitwError.denied("Credential-bearing URLs are not allowed")
                }
            }

            // SCP-like URL: user@host:path
            if a.contains(":") && a.contains("@") && !a.contains("://") {
                throw GitwError.denied("SCP-style Git URLs are not allowed (use https://github.com/…)")
            }

            if a.contains("github.com:") && !a.contains("://") {
                throw GitwError.denied("Non-HTTPS GitHub URLs are not allowed (use https://github.com/…)")
            }
        }
    }
}
