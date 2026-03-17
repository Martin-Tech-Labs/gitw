import Foundation

public protocol KeychainProviding {
    func load(alias: String) throws -> GitwProfile?
    func save(alias: String, profile: GitwProfile) throws
    func delete(alias: String) throws
}

public protocol GitRunning {
    func runGit(args: [String], askpassPath: String, profile: GitwProfile) throws -> Int32
}

public struct RealKeychainProvider: KeychainProviding {
    public init() {}

    public func load(alias: String) throws -> GitwProfile? {
        try KeychainStore.load(alias: alias)
    }

    public func save(alias: String, profile: GitwProfile) throws {
        try KeychainStore.save(alias: alias, profile: profile)
    }

    public func delete(alias: String) throws {
        try KeychainStore.delete(alias: alias)
    }
}

public struct RealGitRunner: GitRunning {
    public init() {}

    public func runGit(args: [String], askpassPath: String, profile: GitwProfile) throws -> Int32 {
        try GitRunner.runGit(args: args, askpassPath: askpassPath, profile: profile)
    }
}

public enum GitwCommand: Equatable {
    case login(alias: String, repoURL: String)
    case logout(alias: String)
    case whoami(alias: String)
    case git(alias: String, args: [String])
}

public struct GitwApp {
    public let keychain: KeychainProviding
    public let git: GitRunning
    public let askpassPath: () -> String

    public init(keychain: KeychainProviding, git: GitRunning, askpassPath: @escaping () -> String) {
        self.keychain = keychain
        self.git = git
        self.askpassPath = askpassPath
    }

    public func run(_ cmd: GitwCommand,
                    ttyReadLine: (String) throws -> String,
                    ttyReadSecret: (String) throws -> String,
                    name: String? = nil,
                    email: String? = nil) throws -> Int32 {
        switch cmd {
        case .whoami(let alias):
            guard (try keychain.load(alias: alias)) != nil else {
                throw GitwError.io("No profile in Keychain for alias \(alias).")
            }
            return 0

        case .logout(let alias):
            try keychain.delete(alias: alias)
            return 0

        case .login(let alias, let repoURL):
            try URLPolicy.validateGitArguments([repoURL])

            guard let name, !name.isEmpty else {
                throw GitwError.usage("login requires --name <name>")
            }
            guard let email, !email.isEmpty else {
                throw GitwError.usage("login requires --email <email>")
            }

            // `--name` is the GitHub username (and also the commit author name we pass via env).
            // Do not prompt for username again.
            let username = name
            let token = try ttyReadSecret("GitHub personal access token: ")

            let profile = GitwProfile(githubUsername: username, token: token, gitName: name, gitEmail: email)

            // Verify using ls-remote via askpass broker (without storing unless it works).
            let status = try git.runGit(
                args: ["ls-remote", repoURL],
                askpassPath: askpassPath(),
                profile: profile
            )
            guard status == 0 else {
                throw GitwError.io("Login check failed (git exit \(status)). Not saved.")
            }

            try keychain.save(alias: alias, profile: profile)
            return 0

        case .git(let alias, let args):
            guard let profile = try keychain.load(alias: alias) else {
                throw GitwError.io("No profile in Keychain for alias \(alias).")
            }
            let status = try git.runGit(args: args, askpassPath: askpassPath(), profile: profile)
            return status
        }
    }
}
