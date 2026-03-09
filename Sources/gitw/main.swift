import Foundation
import GitwCore

private func usage() -> String {
    """
    gitw - secure Git wrapper (GitHub HTTPS + Keychain)

    Usage:
      gitw login <https://github.com/owner/repo.git>
      gitw logout
      gitw whoami
      gitw <git-args...>

    Environment:
      GITW_NAME / GITW_EMAIL   (optional) author/committer identity
      GITW_ASKPASS_PATH       override gitw-askpass path

    """
}

private func askpassPath() -> String {
    if let p = ProcessInfo.processInfo.environment["GITW_ASKPASS_PATH"], !p.isEmpty { return p }

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

    // Default: sibling executable next to gitw.
    let exe = resolveExecutablePath()
    let url = URL(fileURLWithPath: exe)
    let dir = url.deletingLastPathComponent()
    return dir.appendingPathComponent("gitw-askpass").path
}

do {
    var args = CommandLine.arguments
    _ = args.removeFirst()

    if args.isEmpty {
        throw GitwError.usage(usage())
    }

    let cmd = args[0]
    switch cmd {
    case "-h", "--help", "help":
        throw GitwError.usage(usage())
    case "whoami":
        if let c = try KeychainStore.load() {
            print(c.username)
        } else {
            die("No GitHub credentials in Keychain.", code: 1)
        }
    case "logout":
        try KeychainStore.delete()
        print("Deleted GitHub credentials for \(KeychainStore.server) from Keychain.")
    case "login":
        guard args.count >= 2 else {
            throw GitwError.usage("login requires a GitHub HTTPS repo URL\n\n" + usage())
        }
        let repoURL = args[1]
        try URLPolicy.validateGitArguments([repoURL])

        let username = try TTY.readLine(prompt: "GitHub username: ")
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
        print("Credentials stored in Keychain for \(KeychainStore.server).")
    default:
        let creds = try KeychainStore.load()
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
