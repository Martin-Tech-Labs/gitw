import Foundation
import Security

public enum SignatureVerifier {
    // System Git entrypoint.
    //
    // Note: On many macOS setups `/usr/bin/git` is an Apple-signed xcode-select tool shim
    // that dispatches to the active Command Line Tools / Xcode toolchain.
    //
    // You can inspect the designated requirement for a binary with:
    //   codesign -dr - /usr/bin/git 2>&1
    //
    // We keep this strict and baked-in, and we fail closed if it no longer matches.
    public static let systemGitRequirement = "identifier \"com.apple.dt.xcode_select.tool-shim-public\" and anchor apple"

    public static func check(path: String, requirement: String) throws {
        let url = URL(fileURLWithPath: path)
        var staticCode: SecStaticCode?
        let s1 = SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode)
        guard s1 == errSecSuccess, let code = staticCode else {
            throw GitwError.signature("SecStaticCodeCreateWithPath failed: \(s1)")
        }

        var req: SecRequirement?
        let s2 = SecRequirementCreateWithString(requirement as CFString, SecCSFlags(), &req)
        guard s2 == errSecSuccess, let req else {
            throw GitwError.signature("SecRequirementCreateWithString failed: \(s2)")
        }

        let s3 = SecStaticCodeCheckValidity(code, SecCSFlags(), req)
        guard s3 == errSecSuccess else {
            throw GitwError.signature("code signature check failed for \(path) (status \(s3))")
        }
    }
}
