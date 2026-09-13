import Foundation
import ProviderKit

public typealias RefreshRejected = ProviderKit.RefreshRejected

/// Thrown rather than writing over an account list that could not be read.
public struct WouldOverwriteUnreadableAccounts: Error, CustomStringConvertible {
    public var description: String {
        "the stored account list could not be read, and writing would replace the "
        + "only copy of every inactive account's refresh token"
    }
}

/// Declared here rather than in the store's own file, which the new code took
/// past its length limit. Still nested in `CredentialStore`, so every caller
/// keeps the name it already used.
public extension CredentialStore {
    /// How the app obtains a token for this account right now.
    ///
    /// Two states, since every account arrives through the browser: it either
    /// holds a grant of this app's own, or it needs one.
    enum AccountState: Sendable, Hashable {
        case refreshed     // lives on its own refresh token
        case needsLogin    // nothing this app may spend
    }
}
