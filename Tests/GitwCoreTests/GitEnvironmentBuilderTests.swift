import Foundation
import Testing
@testable import GitwCore

struct GitEnvironmentBuilderTests {
    @Test
    func baseEnvironmentIsHardenedAndScrubbed() {
        var base: [String: String] = [
            "GIT_ASKPASS": "evil",
            "SSH_ASKPASS": "evil",
            "GIT_SSH": "evil",
            "GIT_SSH_COMMAND": "evil"
        ]

        let env = GitRunner.buildGitEnvironment(base: base, profile: GitwProfile(githubUsername: "u", token: "t", gitName: "n", gitEmail: "e@example.com"))

        #expect(env["GIT_TERMINAL_PROMPT"] == "0")
        #expect(env["GIT_CONFIG_COUNT"] == "2")
        #expect(env["GIT_CONFIG_KEY_0"] == "credential.helper")
        #expect(env["GIT_CONFIG_VALUE_0"] == "")

        #expect(env["GIT_ASKPASS"] == nil)
        #expect(env["SSH_ASKPASS"] == nil)
        #expect(env["GIT_SSH"] == nil)
        #expect(env["GIT_SSH_COMMAND"] == nil)
    }

    @Test
    func askpassAndBrokerVarsAreSetWhenProvided() {
        let id = String(UUID().uuidString.prefix(8))
        let askpass = "/usr/local/bin/gitw-askpass"
        let sock = "/tmp/sock-\(id)"
        let nonce = UUID().uuidString
        let name = "N-\(id)"
        let email = "e-\(id)@example.com"

        let env = GitRunner.buildGitEnvironment(
            base: [:],
            askpassPath: askpass,
            brokerSocket: sock,
            brokerNonce: nonce,
            profile: GitwProfile(githubUsername: "u-\(id)", token: "t-\(id)", gitName: name, gitEmail: email)
        )

        #expect(env["GIT_ASKPASS"] == askpass)
        #expect(env["SSH_ASKPASS"] == askpass)
        #expect(env["GITW_SOCKET"] == sock)
        #expect(env["GITW_NONCE"] == nonce)
        #expect(env["GIT_AUTHOR_NAME"] == name)
        #expect(env["GIT_AUTHOR_EMAIL"] == email)
        #expect(env["GIT_COMMITTER_NAME"] == name)
        #expect(env["GIT_COMMITTER_EMAIL"] == email)
    }
}
