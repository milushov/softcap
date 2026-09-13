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
    /// Computed rather than stored: the state depends on who the user is signed
    /// in as in the CLI, not on our records.
    public enum AccountState: Sendable, Hashable {
        case activeInCLI   // token read from the CLI keychain, never refreshed
        case refreshed     // lives on its own refresh token copy
        case needsLogin    // no copy, nothing to refresh with
    }
}
