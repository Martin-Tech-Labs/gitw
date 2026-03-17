import Foundation
import Testing
@testable import GitwCore

final class MockKeychain: KeychainProviding {
    var loadedAliases: [String] = []
    var deletedAliases: [String] = []
    var saved: [(alias: String, profile: GitwProfile)] = []
    var profileByAlias: [String: GitwProfile] = [:]

    func load(alias: String) throws -> GitwProfile? {
        loadedAliases.append(alias)
        return profileByAlias[alias]
    }

    func save(alias: String, profile: GitwProfile) throws {
        saved.append((alias, profile))
        profileByAlias[alias] = profile
    }

    func delete(alias: String) throws {
        deletedAliases.append(alias)
        profileByAlias.removeValue(forKey: alias)
    }
}

final class MockGit: GitRunning {
    struct Call: Equatable {
        let args: [String]
        let askpassPath: String
        let githubUsername: String?
        let token: String?
        let name: String?
        let email: String?
    }

    var calls: [Call] = []
    var nextStatus: Int32 = 0

    func runGit(args: [String], askpassPath: String, profile: GitwProfile?) throws -> Int32 {
        calls.append(.init(args: args,
                           askpassPath: askpassPath,
                           githubUsername: profile?.githubUsername,
                           token: profile?.token,
                           name: profile?.gitName,
                           email: profile?.gitEmail))
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
            ttyReadSecret: { _ in "tok" },
            name: "Real Name",
            email: "real@example.com"
        )

        #expect(status == 0)
        #expect(git.calls.count == 1)
        #expect(git.calls[0].args == ["ls-remote", "https://github.com/OWNER/REPO.git"])
        #expect(git.calls[0].githubUsername == "real-user")
        #expect(git.calls[0].name == "Real Name")
        #expect(git.calls[0].email == "real@example.com")
        #expect(kc.saved.count == 1)
        #expect(kc.saved[0].alias == "work")
        #expect(kc.saved[0].profile.githubUsername == "real-user")
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
                ttyReadSecret: { _ in "tok" },
                name: "Real Name",
                email: "real@example.com"
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
        kc.profileByAlias["work"] = GitwProfile(githubUsername: "u", token: "t", gitName: "N", gitEmail: "e@example.com")
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
        #expect(git.calls[0].githubUsername == "u")
    }
}
