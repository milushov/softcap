import Foundation

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
    /// A copy of the refresh token, taken while the account was active in the
    /// CLI. `syncWithCLI` exists for its sake.
    public var refreshToken: String?
    /// Optional on purpose, and it must stay that way.
    ///
    /// `StoredAccount` decodes through the synthesised `Codable`, which refuses
    /// a blob missing any non-optional field — and `load` treats an undecodable
    /// item as "present but unreadable", which then refuses every write to keep
    /// from destroying it. A required field here would put every existing
    /// install into that state at once: no accounts, and no way to add one.
    ///
    /// `nil` means the list predates this field, and the only origin it could
    /// have had is the CLI: the browser path is what introduced it.
    public var tokenOrigin: TokenOrigin?

    /// What `nil` means, written once so the rule is not spelled out at each
    /// use and drifted apart between them.
    public var isOwnGrant: Bool { tokenOrigin == .ownGrant }
}
