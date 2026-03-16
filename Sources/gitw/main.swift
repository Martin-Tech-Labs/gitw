import Foundation
import GitwCore

private func usage() -> String {
    """
    gitw - secure Git wrapper (GitHub HTTPS + Keychain)

    Usage:
      gitw login --as <github_username> <https://github.com/owner/repo.git>
      gitw logout --as <github_username>
      gitw whoami --as <github_username>
      gitw <git-args...> --as <github_username>

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
    let asUser = popFlag("--as")

    let cmd = args[0]
    switch cmd {
    case "-h", "--help", "help":
        throw GitwError.usage(usage())
    case "whoami":
        guard let user = asUser, !user.isEmpty else {
            throw GitwError.usage("whoami requires --as <github_username>\n\n" + usage())
        }
        if let c = try KeychainStore.load(username: user) {
            print(c.username)
        } else {
            die("No GitHub credentials in Keychain for \(user).", code: 1)
        }
    case "logout":
        guard let user = asUser, !user.isEmpty else {
            throw GitwError.usage("logout requires --as <github_username>\n\n" + usage())
        }
        try KeychainStore.delete(username: user)
        print("Deleted GitHub credentials for \(user) (\(KeychainStore.server)) from Keychain.")
    case "login":
        guard let user = asUser, !user.isEmpty else {
            throw GitwError.usage("login requires --as <github_username>\n\n" + usage())
        }
        guard args.count >= 2 else {
            throw GitwError.usage("login requires a GitHub HTTPS repo URL\n\n" + usage())
        }
        let repoURL = args[1]
        try URLPolicy.validateGitArguments([repoURL])

        // Username is the identity selector; don't prompt for it.
        let username = user
        let token = try TTY.readSecret(prompt: "GitHub personal access token: ")

        // Verify using ls-remote via askpass broker (without storing unless it works).
        let status = try GitRunner.runGit(
            args: ["ls-remote", repoURL],
            askpassPath: askpassPath(),
            creds: GitHubCredentials(username: username, token: token)
        )
        guard status == 0 else {
            die("Login check failed (git exit \(status)). Not saved.", code: status)
        }

        try KeychainStore.save(GitHubCredentials(username: username, token: token))
        print("Credentials stored in Keychain for \(username) (\(KeychainStore.server)).")
    default:
        guard let user = asUser, !user.isEmpty else {
            throw GitwError.usage("git invocation requires --as <github_username>\n\n" + usage())
        }
        let creds = try KeychainStore.load(username: user)
        let status = try GitRunner.runGit(args: args, askpassPath: askpassPath(), creds: creds)
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
