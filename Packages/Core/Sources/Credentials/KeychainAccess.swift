import Foundation
import Security
import ProviderKit

/// Reads and writes the one keychain item this app owns.
///
/// There used to be a second item in play — the one Claude Code keeps its own
/// credentials in — and reading an item another app owns is what the keychain
/// puts a dialog on screen for. That read is gone: every account now arrives
/// through the browser and lives in this app's own item, which needs no
/// permission from anybody. `promptIfNeeded` went with it, along with the
/// statuses that meant "somebody would have to allow this": there is no longer
/// a caller who would want the dialog, so the read simply never waits for one.
/// See `read(service:)` for why refusing it is safer than showing it.
public protocol KeychainAccess: Sendable {
    /// Reads an item. `nil` when there is none under that service.
    func read(service: String) async throws -> Data?
    func write(_ data: Data, service: String) async throws
}

public struct SystemKeychain: KeychainAccess {
    public init() {}

    public func read(service: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        // The read never blocks on a dialog.
        //
        // `SecItemCopyMatching` waits, uncancellably, until the keychain's
        // access prompt is answered — and this app has no Dock icon, so a
        // prompt can open behind whatever is in front and be answered by
        // nobody. The one read this app makes happens inside `load()`, on the
        // actor every later call goes through, so a wait there is the whole
        // credential store stopped for as long as it lasts. That was watched
        // happening for eighty-four minutes when a foreign item was still being
        // read.
        //
        // The prompt can still arise for the app's own item: the ACL is bound
        // to the signature that created it, and an ad-hoc signature changes
        // with every build. Refused rather than shown, the read throws, `load`
        // records the item as present-but-unreadable, and nothing is written
        // over it — the accounts are still there for a build that can open it.
        // Blocking instead would trade a recoverable state for a hung app.
        //
        // Process-wide and restored immediately, because the flag belongs to
        // the process rather than to the call.
        #if os(macOS)
        SecKeychainSetUserInteractionAllowed(false)
        #endif
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        #if os(macOS)
        SecKeychainSetUserInteractionAllowed(true)
        #endif

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw ProviderFailure(kind: .needsLogin, diagnostic: "keychain read failed, \(status)")
        }
        return data
    }

    public func write(_ data: Data, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
                throw ProviderFailure(kind: .needsLogin, diagnostic: "keychain add failed")
            }
            return
        }
        guard status == errSecSuccess else {
            throw ProviderFailure(kind: .needsLogin, diagnostic: "keychain update failed")
        }
    }
}
