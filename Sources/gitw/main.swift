import Foundation
import GitwCore

private func usage() -> String {
    """
    gitw - secure Git wrapper (GitHub HTTPS + Keychain)

    Usage:
      gitw login --as <alias> <https://github.com/owner/repo.git>
      gitw logout --as <alias>
      gitw whoami --as <alias>
      gitw <git-args...> --as <alias>

    Environment:
      (none)

    """
}

private func askpassPath() -> String {
    // Security policy: do not allow overriding the askpass helper path via env.
    // The helper must be the sibling executable next to `gitw`.

    func resolveExecutablePath() -> String {
        let argv0 = CommandLine.arguments.first ?? "gitw"
        if argv0.contains("/") {
            return argv0
        }
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in pathEnv.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(argv0).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return argv0
    }

    let exe = resolveExecutablePath()
    let url = URL(fileURLWithPath: exe)
    let dir = url.deletingLastPathComponent()
    return dir.appendingPathComponent("gitw-askpass").path
}

do {
    var args = CommandLine.arguments
    _ = args.removeFirst()

    func popFlag(_ name: String) -> String? {
        if let i = args.firstIndex(of: name), i + 1 < args.count {
            let v = args[i + 1]
            args.removeSubrange(i...i+1)
            return v
        }
        return nil
    }

    if args.isEmpty {
        throw GitwError.usage(usage())
    }

    // `--as` is mandatory for any operation that reads/writes credentials.
    // It is an alias selector (not necessarily the GitHub username).
    guard let alias = popFlag("--as"), !alias.isEmpty else {
        throw GitwError.usage("Missing --as <alias>\n\n" + usage())
    }

    let cmd = args[0]

    let keychain = RealKeychainProvider()
    let app = GitwApp(
        keychain: keychain,
        git: RealGitRunner(),
        askpassPath: askpassPath
    )

    switch cmd {
    case "-h", "--help", "help":
        throw GitwError.usage(usage())
    case "whoami":
        let creds = try keychain.load(alias: alias)
        guard let creds else {
            die("No GitHub credentials in Keychain for alias \(alias).", code: 1)
        }
        print(creds.username)
        exit(0)
    case "logout":
        _ = try app.run(.logout(alias: alias), ttyReadLine: TTY.readLine(prompt:), ttyReadSecret: TTY.readSecret(prompt:))
        print("Deleted GitHub credentials for alias \(alias) (\(KeychainStore.server)) from Keychain.")
        exit(0)
    case "login":
        guard args.count >= 2 else {
            throw GitwError.usage("login requires a GitHub HTTPS repo URL\n\n" + usage())
        }
        let repoURL = args[1]
        // We keep the prompts + verification inside GitwApp, but printing stays here.
        let status = try app.run(.login(alias: alias, repoURL: repoURL), ttyReadLine: TTY.readLine(prompt:), ttyReadSecret: TTY.readSecret(prompt:))
        if status == 0 {
            // Re-load to show the effective username stored for this alias.
            if let c = try keychain.load(alias: alias) {
                print("Credentials stored in Keychain for alias \(alias) (user \(c.username), \(KeychainStore.server)).")
            } else {
                print("Credentials stored in Keychain for alias \(alias) (\(KeychainStore.server)).")
            }
        }
        exit(status)
    default:
        // Everything else is a git invocation.
        let status = try app.run(.git(alias: alias, args: args), ttyReadLine: TTY.readLine(prompt:), ttyReadSecret: TTY.readSecret(prompt:))
        exit(status)
    }
} catch let e as GitwError {
    switch e {
    case .usage(let msg):
        die(msg, code: 0)
    default:
        die("gitw: \(e)")
    }
} catch {
    die("gitw: \(error)")
}
