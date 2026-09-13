import Foundation
import ProviderKit

/// Where an account's refresh token came from, which decides what may be done
/// with it.
public enum TokenOrigin: String, Sendable, Codable, Hashable {
    /// Copied out of the CLI's keychain item while this account was active
    /// there. It is the same token Claude Code holds, so refreshing it while it
    /// is still the active one rotates that token server side and signs the CLI
    /// out. Reading such an account means reading the CLI's item.
    case copiedFromCLI
    /// Issued to this app by its own browser sign-in. A separate grant:
    /// refreshing it rotates our token and nobody else's, so it needs nothing
    /// from the CLI's item and never has to ask for it.
    case ownGrant
}

public struct StoredAccount: Sendable, Codable, Hashable {
    public let id: String
    public let handle: String
    public var displayName: String
    /// The refresh token this app may spend — for a browser account, a grant of
    /// its own. On a list written before `tokenOrigin` existed it may be a copy
    /// taken from Claude Code, which `accessToken(for:)` refuses to spend: the
    /// server rotates a refresh token when it is used, and spending that one
    /// would sign the CLI out.
    public var refreshToken: String?
    /// Optional on purpose, and it must stay that way.
    ///
    /// `StoredAccount` decodes through the synthesised `Codable`, which refuses
    /// a blob missing any non-optional field — and `load` treats an undecodable
    /// item as "present but unreadable", which then refuses every write to keep
    /// from destroying it. A required field here would put every existing
    /// install into that state at once: no accounts, and no way to add one.
    ///
    /// `nil` means the list predates this field and says nothing about where
    /// the token came from — a browser sign-in made by a build from that week
    /// recorded nothing either. It is refused rather than guessed at: of the
    /// two possible mistakes, only spending a CLI copy signs somebody else's
    /// tool out.
    public var tokenOrigin: TokenOrigin?

    /// The access token the last refresh returned, and the moment it stops
    /// being usable — written down beside the refresh token, so a relaunch
    /// serves the poll with what it already has.
    ///
    /// These lived in memory first, on the argument that an access token is
    /// cheap to fetch again. It is not: fetching one spends the refresh token —
    /// the server rotates it on use — and the refresh a relaunch makes is the
    /// most dangerous one there is, because the processes that die are the
    /// ones being replaced, and a reply in flight when the process dies is a
    /// rotation nobody receives. Two accounts were lost to exactly that in one
    /// afternoon of rebuilds.
    ///
    /// Optional for the same reason `tokenOrigin` is: a required field would
    /// turn every existing install's list unreadable at once.
    public var accessToken: String?
    public var accessGoodUntil: Date?

    /// What `nil` means, written once so the rule is not spelled out at each
    /// use and drifted apart between them.
    public var isOwnGrant: Bool { tokenOrigin == .ownGrant }

    /// The stable identifier already carries its namespace. Deriving this
    /// preserves the original keychain format, including pre-OAuth installs.
    public var provider: ProviderID {
        ProviderID(rawValue: String(id.prefix(while: { $0 != "/" }))) ?? .claude
    }
}
