import Foundation
import Darwin
import Testing
@testable import GitwCore

struct IntegrityChecksTests {
    @Test
    func resolveGitPathUsesSystemGit() throws {
        // Note: CI may set GITW_SKIP_GIT_SIGNATURE_CHECK=1 (DEBUG-only bypass).
        let env = try GitRunner.resolveGitPath()
        #expect(env.gitPath == "/usr/bin/git")
        #expect(!env.requirementUsed.isEmpty)
    }

    @Test
    func askpassHashPinningIsEnforced() throws {
        // Create a throwaway executable file that will definitely not match the pinned hash.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitw-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir,
                                                withIntermediateDirectories: false,
                                                attributes: [FileAttributeKey.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: dir) }

        let fakeAskpass = dir.appendingPathComponent("gitw-askpass").path
        FileManager.default.createFile(atPath: fakeAskpass,
                                       contents: Data("#!/bin/sh\necho nope\n".utf8))
        _ = chmod(fakeAskpass, 0o755)

        let creds = GitHubCredentials(username: "u", token: "t")

        do {
            _ = try GitRunner.runGit(args: ["--version"], askpassPath: fakeAskpass, creds: creds)
            Issue.record("Expected runGit to fail due to askpass hash mismatch")
        } catch let e as GitwError {
            switch e {
            case .signature(let msg):
                #expect(msg.contains("hash mismatch"))
            default:
                Issue.record("Expected signature error, got: \(e)")
            }
        }
    }
}
