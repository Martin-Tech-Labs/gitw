import Foundation
import Testing
@testable import GitwCore

final class MockKeychain: KeychainProviding {
    var loadedAliases: [String] = []
    var deletedAliases: [String] = []
    var saved: [(alias: String, creds: GitHubCredentials)] = []
    var credsByAlias: [String: GitHubCredentials] = [:]

    func load(alias: String) throws -> GitHubCredentials? {
        loadedAliases.append(alias)
        return credsByAlias[alias]
    }

    func save(alias: String, creds: GitHubCredentials) throws {
        saved.append((alias, creds))
        credsByAlias[alias] = creds
    }

    func delete(alias: String) throws {
        deletedAliases.append(alias)
        credsByAlias.removeValue(forKey: alias)
    }
}

final class MockGit: GitRunning {
    struct Call: Equatable {
        let args: [String]
        let askpassPath: String
        let username: String?
        let token: String?
    }

    var calls: [Call] = []
    var nextStatus: Int32 = 0

    func runGit(args: [String], askpassPath: String, creds: GitHubCredentials?) throws -> Int32 {
        calls.append(.init(args: args, askpassPath: askpassPath, username: creds?.username, token: creds?.token))
        return nextStatus
    }
}

struct GitwAppTests {
    @Test
    func loginSavesOnlyAfterLsRemoteSucceeds() throws {
        let kc = MockKeychain()
        let git = MockGit()
        git.nextStatus = 0

        let app = GitwApp(keychain: kc, git: git, askpassPath: { "/tmp/gitw-askpass" })

        let status = try app.run(
            .login(alias: "work", repoURL: "https://github.com/OWNER/REPO.git"),
            ttyReadLine: { _ in "real-user" },
            ttyReadSecret: { _ in "tok" }
        )

        #expect(status == 0)
        #expect(git.calls.count == 1)
        #expect(git.calls[0].args == ["ls-remote", "https://github.com/OWNER/REPO.git"])
        #expect(git.calls[0].username == "real-user")
        #expect(kc.saved.count == 1)
        #expect(kc.saved[0].alias == "work")
        #expect(kc.saved[0].creds.username == "real-user")
    }

    @Test
    func loginDoesNotSaveWhenLsRemoteFails() {
        let kc = MockKeychain()
        let git = MockGit()
        git.nextStatus = 2

        let app = GitwApp(keychain: kc, git: git, askpassPath: { "/tmp/gitw-askpass" })

        do {
            _ = try app.run(
                .login(alias: "work", repoURL: "https://github.com/OWNER/REPO.git"),
                ttyReadLine: { _ in "real-user" },
                ttyReadSecret: { _ in "tok" }
            )
            Issue.record("Expected login to fail")
        } catch {
            // expected
        }

        #expect(kc.saved.isEmpty)
    }

    @Test
    func gitCommandLoadsByAliasAndPassesCreds() throws {
        let kc = MockKeychain()
        kc.credsByAlias["work"] = GitHubCredentials(username: "u", token: "t")
        let git = MockGit()

        let app = GitwApp(keychain: kc, git: git, askpassPath: { "/tmp/gitw-askpass" })
        let status = try app.run(
            .git(alias: "work", args: ["status"]),
            ttyReadLine: { _ in "" },
            ttyReadSecret: { _ in "" }
        )

        #expect(status == 0)
        #expect(kc.loadedAliases == ["work"])
        #expect(git.calls.count == 1)
        #expect(git.calls[0].args == ["status"])
        #expect(git.calls[0].username == "u")
    }
}
