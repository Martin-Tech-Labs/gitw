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

public enum KeychainStore {
    // We deliberately keep this fixed; gitw only supports GitHub HTTPS.
    public static let server = "github.com"
    private static let service = "gitw"

    /// Load credentials for a given alias.
    ///
    /// - alias: Local selector key. Not necessarily the GitHub username.
    public static func load(alias: String) throws -> GitHubCredentials? {
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
            let token = String(data: data, encoding: .utf8)
        else {
            throw GitwError.keychain("unexpected keychain item shape")
        }

        // Option B (true alias): store the actual GitHub username in kSecAttrComment.
        // If absent (older installs), fall back to using the account as username.
        let username = (dict[kSecAttrComment as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveUser = (username?.isEmpty == false) ? username! : accountAlias

        return GitHubCredentials(username: effectiveUser, token: token)
    }

    /// Save credentials under a local alias.
    public static func save(alias: String, creds: GitHubCredentials) throws {
        let data = Data(creds.token.utf8)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: server,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            // Account is the selector alias.
            kSecAttrAccount as String: alias,
            // Store actual GitHub username separately.
            kSecAttrComment as String: creds.username,
            kSecValueData as String: data,
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
                kSecAttrComment as String: creds.username,
                kSecValueData as String: data
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
