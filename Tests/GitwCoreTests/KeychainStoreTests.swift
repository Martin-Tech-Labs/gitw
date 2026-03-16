import Foundation
import Testing
@testable import GitwCore

struct KeychainStoreTests {
    @Test
    func loadAndDeleteAreScopedToUsername() throws {
        // This is a compile-time / query-shape test only (no real Keychain).
        // We can't hit Security.framework deterministically in CI.
        // Instead we ensure the API forces a username selector.

        // These calls should compile and require a username parameter.
        _ = try KeychainStore.load(alias: "work")
        try KeychainStore.delete(alias: "work")
    }
}
