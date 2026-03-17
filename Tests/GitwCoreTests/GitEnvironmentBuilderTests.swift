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

        let env = GitRunner.buildGitEnvironment(base: base)

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
        let env = GitRunner.buildGitEnvironment(
            base: [:],
            askpassPath: "/usr/local/bin/gitw-askpass",
            brokerSocket: "/tmp/sock",
            brokerNonce: "nonce",
            profile: GitwProfile(githubUsername: "u", token: "t", gitName: "N", gitEmail: "e@example.com")
        )

        #expect(env["GIT_ASKPASS"] == "/usr/local/bin/gitw-askpass")
        #expect(env["SSH_ASKPASS"] == "/usr/local/bin/gitw-askpass")
        #expect(env["GITW_SOCKET"] == "/tmp/sock")
        #expect(env["GITW_NONCE"] == "nonce")
        #expect(env["GIT_AUTHOR_NAME"] == "N")
        #expect(env["GIT_AUTHOR_EMAIL"] == "e@example.com")
        #expect(env["GIT_COMMITTER_NAME"] == "N")
        #expect(env["GIT_COMMITTER_EMAIL"] == "e@example.com")
    }
}
