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
    // Keychain namespace. We still authenticate against github.com, but we store credentials
    // under a dedicated Keychain server name to avoid collisions with other GitHub tooling.
    public static let server = "gitw.github.com"
    private static let service = "gitw"

    /// Load credentials for a given alias.
    ///
    /// - alias: Local selector key. Not necessarily the GitHub username.
    public static func load(alias: String) throws -> GitwProfile? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: server,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            kSecAttrAccount as String: alias,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecAttrLabel as String: service
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
            let data = dict[kSecValueData as String] as? Data,
            let _ = String(data: data, encoding: .utf8)
        else {
            throw GitwError.keychain("unexpected keychain item shape")
        }

        // Primary storage: JSON in kSecAttrGeneric.
        if let generic = dict[kSecAttrGeneric as String] as? Data {
            do {
                let p = try JSONDecoder().decode(GitwProfile.self, from: generic)
                return p
            } catch {
                throw GitwError.keychain("failed to decode profile JSON: \(error)")
            }
        }

        // Name/email not present in legacy entries; we fail closed because the design now requires them.
        let username = (dict[kSecAttrComment as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hint = (username?.isEmpty == false) ? username! : accountAlias
        throw GitwError.keychain("profile for alias \(accountAlias) is missing name/email (legacy entry). Please re-run: gitw login --as \(accountAlias) --name ... --email ... (github username was \(hint))")
    }

    /// Save credentials under a local alias.
    public static func save(alias: String, profile: GitwProfile) throws {
        let tokenData = Data(profile.token.utf8)
        let generic = try JSONEncoder().encode(profile)

        let attrs: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: server,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            // Account is the selector alias.
            kSecAttrAccount as String: alias,
            // Store actual GitHub username separately (also kept for human inspection).
            kSecAttrComment as String: profile.githubUsername,
            // Store full profile JSON.
            kSecAttrGeneric as String: generic,
            // Secret token stays as value data.
            kSecValueData as String: tokenData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrLabel as String: service
        ]

        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let query: [String: Any] = [
                kSecClass as String: kSecClassInternetPassword,
                kSecAttrServer as String: server,
                kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
                kSecAttrAccount as String: alias,
                kSecAttrLabel as String: service
            ]
            let update: [String: Any] = [
                kSecAttrComment as String: profile.githubUsername,
                kSecAttrGeneric as String: generic,
                kSecValueData as String: tokenData
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
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: server,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            kSecAttrAccount as String: alias,
            kSecAttrLabel as String: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound { return }
        guard status == errSecSuccess else {
            throw GitwError.keychain("SecItemDelete failed: \(status)")
        }
    }
}
