import Foundation
import Security

public struct GitHubCredentials: Sendable {
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

    public static func load(username: String) throws -> GitHubCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: server,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            kSecAttrAccount as String: username,
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
            let account = dict[kSecAttrAccount as String] as? String,
            let data = dict[kSecValueData as String] as? Data,
            let token = String(data: data, encoding: .utf8)
        else {
            throw GitwError.keychain("unexpected keychain item shape")
        }
        return GitHubCredentials(username: account, token: token)
    }

    public static func save(_ creds: GitHubCredentials) throws {
        let data = Data(creds.token.utf8)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: server,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            kSecAttrAccount as String: creds.username,
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
                kSecAttrLabel as String: service
            ]
            let update: [String: Any] = [
                kSecAttrAccount as String: creds.username,
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

    public static func delete(username: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: server,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            kSecAttrAccount as String: username,
            kSecAttrLabel as String: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound { return }
        guard status == errSecSuccess else {
            throw GitwError.keychain("SecItemDelete failed: \(status)")
        }
    }
}
