import Foundation
import Security

public struct GitHubCredentials: Sendable {
    /// The actual GitHub username used for HTTP auth.
    public let username: String
    public let token: String

    public init(username: String, token: String) {
        self.username = username
        self.token = token
    }
}

/// Full per-alias profile stored in Keychain.
public struct GitwProfile: Sendable, Codable, Equatable {
    public let githubUsername: String
    public let token: String
    public let gitName: String
    public let gitEmail: String

    public init(githubUsername: String, token: String, gitName: String, gitEmail: String) {
        self.githubUsername = githubUsername
        self.token = token
        self.gitName = gitName
        self.gitEmail = gitEmail
    }

    public var creds: GitHubCredentials { .init(username: githubUsername, token: token) }
}

public enum KeychainStore {
    // Keychain namespace. We store the full profile as a single Keychain item.
    // Use a dedicated service name to avoid collisions with other tooling.
    public static let service = "gitw.github.com"

    /// Load credentials for a given alias.
    ///
    /// - alias: Local selector key. Not necessarily the GitHub username.
    public static func load(alias: String) throws -> GitwProfile? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: alias,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw GitwError.keychain("SecItemCopyMatching failed: \(status)")
        }
        guard
            let dict = item as? [String: Any],
            let accountAlias = dict[kSecAttrAccount as String] as? String,
            let data = dict[kSecValueData as String] as? Data
        else {
            throw GitwError.keychain("unexpected keychain item shape")
        }

        do {
            return try JSONDecoder().decode(GitwProfile.self, from: data)
        } catch {
            // Fail closed: profile is required for gitw to operate.
            throw GitwError.keychain("profile for alias \(accountAlias) is missing profile metadata (expected JSON). Please re-run login for this alias.")
        }
    }

    /// Save credentials under a local alias.
    public static func save(alias: String, profile: GitwProfile) throws {
        let json = try JSONEncoder().encode(profile)

        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            // Account is the selector alias.
            kSecAttrAccount as String: alias,
            // Full profile JSON stored as the secret payload.
            kSecValueData as String: json,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: alias
            ]
            let update: [String: Any] = [
                kSecValueData as String: json
            ]
            let s2 = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard s2 == errSecSuccess else {
                throw GitwError.keychain("SecItemUpdate failed: \(s2)")
            }
            return
        }
        guard status == errSecSuccess else {
            throw GitwError.keychain("SecItemAdd failed: \(status)")
        }
    }

    public static func delete(alias: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: alias
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound { return }
        guard status == errSecSuccess else {
            throw GitwError.keychain("SecItemDelete failed: \(status)")
        }
    }
}
