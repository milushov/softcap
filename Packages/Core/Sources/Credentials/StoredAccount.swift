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
    /// Typed in by the person whose key it is.
    ///
    /// Not `ownGrant`: nothing was granted to this app, and calling it one
    /// would make `isOwnGrant` a lie in the one place the word carries weight.
    /// Not `copiedFromCLI` either — nothing was read from anybody's files.
    ///
    /// Safe to spend for the reason the CLI rule exists at all: that rule is
    /// about *rotation*. Spending a refresh token copied from a CLI retires the
    /// CLI's copy and signs it out. A static key rotates nothing, so reading a
    /// quota with it leaves the person's own editor working exactly as before.
    case givenByHand
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

    /// Decoded by hand for one field, and only to keep a value this build has
    /// not met from costing every account in the item.
    ///
    /// The synthesised decoder refuses an unknown `tokenOrigin` by throwing,
    /// and `load` reads a blob it cannot decode as "present but unreadable" —
    /// which then refuses every write, so the whole list goes, Claude and Codex
    /// with it, and the only thing offered is starting over. One origin nobody
    /// has heard of should cost one row.
    ///
    /// An unknown origin becomes `nil`, which is already the most cautious
    /// answer this type has: refused for spending, and recovered by signing
    /// that account in again.
    ///
    /// This protects builds from here on and not the ones already out. Adding
    /// `givenByHand` is a value older copies cannot read, and the only way to
    /// have avoided that was to not name the thing accurately. The cost is
    /// written in `docs/DECISIONS.md` rather than paid by a silent lie in the
    /// data.
    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decode(String.self, forKey: .id)
        handle = try box.decode(String.self, forKey: .handle)
        displayName = try box.decode(String.self, forKey: .displayName)
        refreshToken = try box.decodeIfPresent(String.self, forKey: .refreshToken)
        tokenOrigin = ((try? box.decodeIfPresent(String.self, forKey: .tokenOrigin)) ?? nil)
            .flatMap(TokenOrigin.init(rawValue:))
        accessToken = try box.decodeIfPresent(String.self, forKey: .accessToken)
        accessGoodUntil = try box.decodeIfPresent(Date.self, forKey: .accessGoodUntil)
    }

    /// The memberwise initialiser, written out because declaring `init(from:)`
    /// above does not remove the synthesised one but this file now owns both.
    /// The defaults match what the compiler gave: an optional left out is `nil`,
    /// which several call sites rely on.
    public init(
        id: String, handle: String, displayName: String, refreshToken: String? = nil,
        tokenOrigin: TokenOrigin? = nil, accessToken: String? = nil,
        accessGoodUntil: Date? = nil
    ) {
        self.id = id
        self.handle = handle
        self.displayName = displayName
        self.refreshToken = refreshToken
        self.tokenOrigin = tokenOrigin
        self.accessToken = accessToken
        self.accessGoodUntil = accessGoodUntil
    }

    /// What `nil` means, written once so the rule is not spelled out at each
    /// use and drifted apart between them.
    public var isOwnGrant: Bool { tokenOrigin == .ownGrant }

    /// Whether this app may use the credential at all.
    ///
    /// Two origins qualify and one does not. A grant of our own may be spent
    /// because it is ours; a key given by hand may be used because using it
    /// rotates nothing and can sign nothing out. A token copied from a CLI is
    /// refused, and `nil` — a list written before this field existed — is
    /// refused with it, because of the two possible mistakes only one signs
    /// somebody else's tool out.
    public var isSpendable: Bool {
        tokenOrigin == .ownGrant || tokenOrigin == .givenByHand
    }

    /// The stable identifier already carries its namespace. Deriving this
    /// preserves the original keychain format, including pre-OAuth installs.
    public var provider: ProviderID {
        ProviderID(rawValue: String(id.prefix(while: { $0 != "/" }))) ?? .claude
    }
}
