import Foundation
import Security

public struct GitEnvironment {
    public let gitPath: String
    public let requirementUsed: String

    public init(gitPath: String, requirementUsed: String) {
        self.gitPath = gitPath
        self.requirementUsed = requirementUsed
    }
}

public enum GitRunner {
    /// Resolve the Git binary we will execute.
    ///
    /// Security policy (intentional):
    /// - Only allow the Apple system entrypoint at `/usr/bin/git`.
    /// - Verify its code signature against a baked-in requirement.
    /// - No PATH lookups, no `xcrun --find`, no fallbacks.
    public static func resolveGitPath() throws -> GitEnvironment {
        let systemGit = "/usr/bin/git"
        let req = SignatureVerifier.systemGitRequirement
        try SignatureVerifier.check(path: systemGit, requirement: req)
        return GitEnvironment(gitPath: systemGit, requirementUsed: req)
    }

    public static func runGit(args: [String], askpassPath: String, creds: GitHubCredentials?) throws -> Int32 {
        // Always validate arguments we can see.
        try URLPolicy.validateGitArguments(args)

        let gitEnv = try resolveGitPath()

        // If this looks like a remote/networking command and no explicit URL was provided,
        // sanity-check remotes in the current repo to enforce GitHub HTTPS.
        if shouldValidateRepoRemotes(args: args) {
            try validateRepoRemotes(gitPath: gitEnv.gitPath, prefixArgs: extractGitPrefixArgs(args))
        }

        var env = ProcessInfo.processInfo.environment
        // Fail closed: never allow terminal prompting.
        env["GIT_TERMINAL_PROMPT"] = "0"

        // Disable helpers so creds never spill to disk, keychain via git, or other helpers.
        env["GIT_CONFIG_COUNT"] = "2"
        env["GIT_CONFIG_KEY_0"] = "credential.helper"
        env["GIT_CONFIG_VALUE_0"] = ""
        env["GIT_CONFIG_KEY_1"] = "credential.useHttpPath"
        env["GIT_CONFIG_VALUE_1"] = "true"


        // Scrub potentially dangerous overrides.
        env["GIT_ASKPASS"] = nil
        env["SSH_ASKPASS"] = nil
        env["GIT_SSH"] = nil
        env["GIT_SSH_COMMAND"] = nil

        var broker: AskpassBroker?
        var tmpDir: URL?
        if let creds {
            guard FileManager.default.isExecutableFile(atPath: askpassPath) else {
                throw GitwError.io("askpass helper not found or not executable at: \(askpassPath)")
            }
            let nonce = randomNonce()
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitw-\(getpid())-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [FileAttributeKey.posixPermissions: 0o700])
            tmpDir = dir
            let sock = dir.appendingPathComponent("askpass.sock").path

            // Askpass integrity: hash-pin the helper *and* avoid TOCTOU by copying it
            // into our private temp dir and executing the copy.
            let stagedAskpass = dir.appendingPathComponent("gitw-askpass").path
            try FileManager.default.copyItem(atPath: askpassPath, toPath: stagedAskpass)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stagedAskpass)
            let actualHash = try Hashing.sha256Hex(fileAtPath: stagedAskpass)
            guard actualHash == AskpassTrust.expectedAskpassSHA256 else {
                throw GitwError.signature("gitw-askpass hash mismatch (expected \(AskpassTrust.expectedAskpassSHA256), got \(actualHash))")
            }

            let cfg = BrokerConfig(socketPath: sock, nonce: nonce, timeoutSeconds: 20, username: creds.username, token: creds.token)
            let b = AskpassBroker(cfg: cfg)
            try b.start()
            broker = b

            env["GIT_ASKPASS"] = stagedAskpass
            env["SSH_ASKPASS"] = stagedAskpass
            env["GITW_SOCKET"] = sock
            env["GITW_NONCE"] = nonce
        } else {
            // No credentials. Askpass is not set; git will fail closed if it prompts.
        }

        defer {
            broker?.close()
            if let tmpDir {
                try? FileManager.default.removeItem(at: tmpDir)
            }
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: gitEnv.gitPath)
        p.arguments = args
        p.environment = env
        p.standardInput = FileHandle.standardInput
        p.standardOutput = FileHandle.standardOutput
        p.standardError = FileHandle.standardError

        try p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }

    public static func runAndCapture(_ path: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let rc = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if rc == errSecSuccess {
            return Data(bytes).base64EncodedString()
        }
        // Fallback: UUID
        return UUID().uuidString
    }

    private static func shouldValidateRepoRemotes(args: [String]) -> Bool {
        // If any explicit URL argument exists, URLPolicy already checked it.
        if args.contains(where: { $0.contains("://") || $0.hasPrefix("git@") || ($0.contains(":") && $0.contains("@")) }) {
            return false
        }
        guard let sub = args.first(where: { !$0.hasPrefix("-") })?.lowercased() else { return false }
        switch sub {
        case "fetch", "pull", "push", "remote", "submodule", "ls-remote":
            return true
        default:
            return false
        }
    }

    private static func extractGitPrefixArgs(_ args: [String]) -> [String] {
        // Preserve common prefix options that affect repo location.
        var out: [String] = []
        var i = 0
        while i < args.count {
            let a = args[i]
            if a == "-C", i + 1 < args.count {
                out.append(a)
                out.append(args[i + 1])
                i += 2
                continue
            }
            if a == "--git-dir", i + 1 < args.count {
                out.append(a)
                out.append(args[i + 1])
                i += 2
                continue
            }
            if a == "--work-tree", i + 1 < args.count {
                out.append(a)
                out.append(args[i + 1])
                i += 2
                continue
            }
            i += 1
        }
        return out
    }

    private static func validateRepoRemotes(gitPath: String, prefixArgs: [String]) throws {
        // If we're not in a repo, this will fail; ignore.
        let output: String
        do {
            output = try runGitAndCapture(gitPath: gitPath, args: prefixArgs + ["remote", "-v"])
        } catch {
            return
        }

        for line in output.split(separator: "\n") {
            // origin\thttps://github.com/owner/repo (fetch)
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count >= 2 {
                let url = String(parts[1])
                try URLPolicy.validateGitArguments([url])
            }
        }
    }

    private static func runGitAndCapture(gitPath: String, args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: gitPath)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_CONFIG_COUNT"] = "1"
        env["GIT_CONFIG_KEY_0"] = "credential.helper"
        env["GIT_CONFIG_VALUE_0"] = ""
        p.environment = env
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw GitwError.git("git remote validation failed")
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
