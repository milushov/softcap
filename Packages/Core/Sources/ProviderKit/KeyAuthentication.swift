import Foundation
import CryptoKit

/// A service whose credential is handed over rather than granted.
///
/// The other two shapes both end with the service issuing something: a browser
/// redirect carries a code back, a device grant is polled for one. This one has
/// no flow at all. The person already holds a key — their plan issued it, their
/// editor uses it — and the whole of signing in is giving it to us.
///
/// So there is nothing here for `LoginController` to drive: no port to bind, no
/// interval to keep, no deadline. One request proves the key works and says
/// what the account is called, and that request is the sign-in.
public protocol KeyAuthenticating: Sendable {
    var provider: ProviderID { get }

    /// Uses the key once, to find out whether it works and what to call the
    /// account it belongs to. Throws `ProviderFailure` when it does not.
    func account(for key: String) async throws -> AuthenticatedAccount
}

public extension KeyAuthenticating {
    /// A stable, opaque name for the account a key belongs to.
    ///
    /// Every other service answers who its account is, and the answer becomes
    /// the handle. A service that answers nothing still needs one, because the
    /// identifier is what a saved account is found by — and a fresh identifier
    /// each time would file the same key twice, leaving a person with two rows
    /// they cannot tell apart and no way to remove either.
    ///
    /// Derived from the key so that giving the same key again lands on the same
    /// account. Hashed, and truncated, because the identifier is written to the
    /// keychain item, read back into snapshots and printed in diagnostics; the
    /// key itself may appear in none of those. Sixteen hex characters is not a
    /// number anybody will collide with by accident and is short enough to read
    /// in a log.
    func handle(forKey key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }
}
