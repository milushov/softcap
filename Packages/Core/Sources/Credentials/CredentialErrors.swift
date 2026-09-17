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

/// Why the saved account list could not be read, and therefore what gets it
/// back.
///
/// The two used to be one flag, and the interface could only say "Sign-in did
/// not complete" to either. They are not the same situation: one has a way out
/// that costs nothing, and the other has no way out at all.
public enum UnreadableAccountList: Sendable, Hashable {
    /// The keychain would not open the item for this build. Access is bound to
    /// the signature that wrote it, and a build signed ad-hoc is a different
    /// application every time it is built — so an update is enough to produce
    /// this. Nothing is lost: the keychain will put the question to the person,
    /// and their answer hands the accounts back intact.
    case keychainRefusedThisBuild
    /// The keychain did not answer at all — locked, missing, or broken. Asking
    /// is still worth a try, since an unlock is a question too, but nothing
    /// here establishes *why*, and a screen that named a cause it had not
    /// established would be guessing beside a button that deletes tokens.
    case keychainDidNotOpen
    /// The item opened and what came out could not be understood. There is
    /// nobody to ask about this one and nothing they could usefully say, so the
    /// only way on is to start over — at the cost of every refresh token in it.
    case contentNotUnderstood
}

/// Thrown when the list was asked to open and stayed shut.
///
/// `whyUnreadable()` says which of the two it is afterwards, and it can have
/// changed: a read that was refused and is then allowed can still turn out to
/// hold something this build cannot understand.
public struct AccountListStayedShut: Error, CustomStringConvertible {
    public var description: String { "the saved account list did not open" }
}

/// Thrown when starting over is asked for over a list that reads perfectly
/// well.
///
/// Starting over deletes the only copy of every refresh token in the item. It
/// is offered from exactly one state — the one where those tokens cannot be
/// reached anyway — and this refuses the call from anywhere else rather than
/// trusting every future caller to have checked.
public struct NothingToStartOverFrom: Error, CustomStringConvertible {
    public var description: String {
        "the account list reads correctly; there is nothing to start over from"
    }
}
