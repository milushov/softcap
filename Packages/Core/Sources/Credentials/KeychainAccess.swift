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
///
/// `readAllowingPrompt` is the one exception, and it is not a reversal of that:
/// it is never reached by a poll or by launch, only by a person pressing a
/// button that says what it is about to do.
public protocol KeychainAccess: Sendable {
    /// Reads an item. `nil` when there is none under that service.
    func read(service: String) async throws -> Data?
    /// Reads, and lets the keychain put its own access question on screen when
    /// the item's access control needs one answered.
    func readAllowingPrompt(service: String) async throws -> Data?
    func write(_ data: Data, service: String) async throws
    /// Puts a new item where the old one was, rather than writing into it.
    ///
    /// The difference is the access control. Writing into an item leaves the
    /// old one in place with the access it already had — measured: an update
    /// from a build the item does not belong to succeeds, and the item still
    /// cannot be read afterwards. Storing accounts that way would put them
    /// somewhere this app can never open again.
    func replace(_ data: Data, service: String) async throws
}

public extension KeychainAccess {
    /// For a store with no access control of its own — the in-memory ones the
    /// tests use — asking changes nothing, and replacing is writing.
    func readAllowingPrompt(service: String) async throws -> Data? {
        try await read(service: service)
    }
    func replace(_ data: Data, service: String) async throws {
        try await write(data, service: service)
    }
}

/// What the keychain answered when it would not hand the item over.
///
/// The number is kept rather than turned into a sentence at the throw site,
/// because the two things a caller wants from it are different: the log wants
/// the number, and the interface wants to know whether a person can do anything
/// about it. Flattened into one error, every failure read as the same failure —
/// and the screen went on to state a cause it had not established, beside a
/// button that deletes every token in the item.
public struct KeychainDidNotOpen: Error, CustomStringConvertible, Sendable {
    public let status: OSStatus

    public init(status: OSStatus) { self.status = status }

    /// Whether the item's access control turned this caller away, as opposed to
    /// the keychain being unable to answer at all.
    ///
    /// `errSecAuthFailed` is what a build the item does not belong to is told
    /// once the dialog is refused; `errSecInteractionNotAllowed` is what it is
    /// told when there is no dialog to refuse. Both mean a person could allow
    /// it. Anything else — a keychain that is locked, missing, or broken —
    /// means something else, and saying "this copy of the app is not the one
    /// that saved them" about it would be a guess stated as a fact.
    public var isAboutThisBuild: Bool {
        status == errSecAuthFailed || status == errSecInteractionNotAllowed
    }

    public var description: String { "keychain read failed, \(status)" }
}

/// Thrown when the old item was deleted and nothing could be put in its place.
///
/// Distinct because the difference matters to the only caller: what the item
/// held is already gone, so the guard that exists to protect it is now guarding
/// nothing, and a store that goes on refusing writes would be stuck for good.
public struct TheItemWasDeletedAndNotReplaced: Error, CustomStringConvertible {
    public let status: OSStatus

    public init(status: OSStatus) { self.status = status }

    public var description: String {
        "the old keychain item was deleted and the replacement failed, \(status)"
    }
}

public struct SystemKeychain: KeychainAccess {
    public init() {}

    private static func query(_ service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
    }

    /// The read both entry points share. `asking` is the only difference
    /// between them, and it is the difference between a question on screen and
    /// an immediate refusal.
    private static func copy(service: String, asking: Bool) throws -> Data? {
        var query = query(service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        // The flag is process-wide and is restored immediately, because it
        // belongs to the process rather than to the call.
        #if os(macOS)
        SecKeychainSetUserInteractionAllowed(asking)
        #endif
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        #if os(macOS)
        SecKeychainSetUserInteractionAllowed(true)
        #endif

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainDidNotOpen(status: status)
        }
        return data
    }

    public func read(service: String) throws -> Data? {
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
        // over it — the accounts are still there for a build that can open it,
        // and `readAllowingPrompt` is how a person asks for this one to become
        // such a build. Blocking instead would trade a recoverable state for a
        // hung app.
        try Self.copy(service: service, asking: false)
    }

    /// Reads with the keychain's question allowed, off the caller's executor.
    ///
    /// The call blocks until the question is answered and cannot be cancelled,
    /// so what waits here is one background thread rather than the actor every
    /// credential in the app goes through. That is the whole difference between
    /// a person taking their time over a dialog and an app that has stopped:
    /// polls, the menu, and the window all keep working while it stands open.
    public func readAllowingPrompt(service: String) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try Self.copy(service: service, asking: true))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func write(_ data: Data, service: String) throws {
        let query = Self.query(service)
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

    /// Deletes the item and adds a new one, so that what comes back belongs to
    /// this build and can be read without asking anybody ever again.
    ///
    /// Deleted through its reference rather than by query. `SecItemDelete` on
    /// the query refuses an item this build does not own — `-25244`, "invalid
    /// attempt to change the owner of this item" — and does so whether or not
    /// the keychain is allowed to ask. Taking the reference decrypts nothing,
    /// so there is no access question in the way of it, and the delete that
    /// follows succeeds where the other one cannot. Both were measured before
    /// this was written.
    ///
    /// Off the caller's executor, for the same reason the asking read is: a
    /// locked keychain answers a delete with an unlock prompt, and that prompt
    /// blocks uncancellably. Held on the store's actor it would stop every poll
    /// and every token vend behind it.
    public func replace(_ data: Data, service: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try Self.deleteThenAdd(data, service: service)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func deleteThenAdd(_ data: Data, service: String) throws {
        var deleted = false
        #if os(macOS)
        var reference: CFTypeRef?
        var lookup = query(service)
        lookup[kSecReturnRef as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        let found = SecItemCopyMatching(lookup as CFDictionary, &reference)
        if found == errSecSuccess {
            // A conditional cast, because a trap inside a repair a person asked
            // for is the one outcome worse than the repair failing. Everything
            // in a file-based keychain comes back as a `SecKeychainItem`; an
            // item that does not is one this path cannot delete, and saying so
            // leaves the accounts where they are.
            guard let item = reference, CFGetTypeID(item) == SecKeychainItemGetTypeID() else {
                throw KeychainDidNotOpen(status: errSecInvalidItemRef)
            }
            // swiftlint:disable:next force_cast
            let status = SecKeychainItemDelete(item as! SecKeychainItem)
            guard status == errSecSuccess else { throw KeychainDidNotOpen(status: status) }
            deleted = true
        } else if found != errSecItemNotFound {
            throw KeychainDidNotOpen(status: found)
        }
        #else
        deleted = SecItemDelete(query(service) as CFDictionary) == errSecSuccess
        #endif

        var insert = query(service)
        insert[kSecValueData as String] = data
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status != errSecSuccess else { return }
        // What the item held is gone either way. Which side of the delete the
        // failure fell on is the whole difference to the caller: before it,
        // nothing has happened and the accounts are still there; after it,
        // there is no item at all, and a store that went on guarding the
        // tokens it used to hold would refuse every write for good.
        throw deleted
            ? TheItemWasDeletedAndNotReplaced(status: status)
            : KeychainDidNotOpen(status: status)
    }
}
