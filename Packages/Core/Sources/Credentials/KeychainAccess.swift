import Foundation
import Security
import ProviderKit

public protocol KeychainAccess: Sendable {
    /// Reads an item.
    ///
    /// `promptIfNeeded` decides what happens when the keychain would have to ask
    /// the person for permission — which it does for an item another app owns,
    /// once, until they choose "Always Allow".
    ///
    /// A poll must pass `false`. `SecItemCopyMatching` blocks until the dialog is
    /// answered, and a dialog raised by a five-minute timer is one nobody is
    /// looking for: watched sitting unanswered for eighty-four minutes with the
    /// app frozen behind it. Passing `false` turns that wait into an immediate
    /// error the interface can show.
    ///
    /// `true` belongs to actions a person just took, where the dialog appears
    /// while they are watching.
    func read(service: String, promptIfNeeded: Bool) async throws -> Data?
    func write(_ data: Data, service: String) async throws
}

public extension KeychainAccess {
    /// Defaults to not asking. The unattended path is the common one, and the
    /// dangerous default is the one that blocks.
    func read(service: String) async throws -> Data? {
        try await read(service: service, promptIfNeeded: false)
    }
}

/// Which keychain statuses mean "a person would have to allow this".
///
/// Written down separately because the obvious one is not the one that arrives.
/// Reading an item another app owns with user interaction switched off returns
/// **`errSecAuthFailed` (-25293)**, not `errSecInteractionNotAllowed` (-25308) —
/// checked against the running app, where the CLI's item answered -25293 while
/// the app's own item answered 0. Matching only the obvious status left the
/// refusal reported as an ordinary read failure, which advises signing in again:
/// the one action that cannot help.
public enum KeychainRefusal {
    /// The failure to throw, or `nil` if this status is not a refusal.
    ///
    /// `errSecAuthFailed` covers both cases and both mean the same thing to the
    /// app: with interaction off it is the dialog that was not shown, and with
    /// interaction on it is the dialog that was answered with Deny. Either way
    /// the way forward is to allow access, not to sign in.
    public static func failure(for status: OSStatus) -> ProviderFailure? {
        switch status {
        case errSecInteractionNotAllowed:
            return ProviderFailure(kind: .needsPermission,
                                   diagnostic: "keychain would have prompted; not asking from a poll")
        case errSecAuthFailed:
            return ProviderFailure(kind: .needsPermission,
                                   diagnostic: "keychain access not granted (-25293)")
        default:
            return nil
        }
    }
}

public struct SystemKeychain: KeychainAccess {
    public init() {}

    public func read(service: String, promptIfNeeded: Bool) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        // Process-wide and restored immediately, because it has to be: the flag
        // belongs to the process, not to the call, and leaving it off would deny
        // the dialog to the places that want it.
        //
        // macOS only. The dialog it suppresses is the access-control prompt of
        // the file-based keychain, which asks before letting one app read an
        // item another app owns — reading the CLI's credentials is exactly that.
        // iOS has no such prompt and no such function.
        #if os(macOS)
        if !promptIfNeeded { SecKeychainSetUserInteractionAllowed(false) }
        #endif
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        #if os(macOS)
        if !promptIfNeeded { SecKeychainSetUserInteractionAllowed(true) }
        #endif

        if status == errSecItemNotFound { return nil }
        if let refusal = KeychainRefusal.failure(for: status) { throw refusal }
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
