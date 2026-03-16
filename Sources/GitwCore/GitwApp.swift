import Foundation

public protocol KeychainProviding {
    func load(alias: String) throws -> GitHubCredentials?
    func save(alias: String, creds: GitHubCredentials) throws
    func delete(alias: String) throws
}

public protocol GitRunning {
    func runGit(args: [String], askpassPath: String, creds: GitHubCredentials?) throws -> Int32
}

public struct RealKeychainProvider: KeychainProviding {
    public init() {}

    public func load(alias: String) throws -> GitHubCredentials? {
        try KeychainStore.load(alias: alias)
    }

    public func save(alias: String, creds: GitHubCredentials) throws {
        try KeychainStore.save(alias: alias, creds: creds)
    }

    public func delete(alias: String) throws {
        try KeychainStore.delete(alias: alias)
    }
}

public struct RealGitRunner: GitRunning {
    public init() {}

    public func runGit(args: [String], askpassPath: String, creds: GitHubCredentials?) throws -> Int32 {
        try GitRunner.runGit(args: args, askpassPath: askpassPath, creds: creds)
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
                    ttyReadSecret: (String) throws -> String) throws -> Int32 {
        switch cmd {
        case .whoami(let alias):
            guard (try keychain.load(alias: alias)) != nil else {
                throw GitwError.io("No GitHub credentials in Keychain for alias \(alias).")
            }
            return 0

        case .logout(let alias):
            try keychain.delete(alias: alias)
            return 0

        case .login(let alias, let repoURL):
            try URLPolicy.validateGitArguments([repoURL])

            let username = try ttyReadLine("GitHub username: ")
            let token = try ttyReadSecret("GitHub personal access token: ")

            // Verify using ls-remote via askpass broker (without storing unless it works).
            let status = try git.runGit(
                args: ["ls-remote", repoURL],
                askpassPath: askpassPath(),
                creds: GitHubCredentials(username: username, token: token)
            )
            guard status == 0 else {
                throw GitwError.io("Login check failed (git exit \(status)). Not saved.")
            }

            try keychain.save(alias: alias, creds: GitHubCredentials(username: username, token: token))
            return 0

        case .git(let alias, let args):
            let creds = try keychain.load(alias: alias)
            let status = try git.runGit(args: args, askpassPath: askpassPath(), creds: creds)
            return status
        }
    }
}
