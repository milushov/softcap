import Foundation

/// A reference to an account, enough to go and fetch it.
///
/// `handle` is whatever the provider navigates by: a Claude account uuid, a
/// Codex account identifier, and so on.
public struct AccountRef: Sendable, Hashable, Identifiable {
    public let id: String
    public let provider: ProviderID
    public let handle: String
    /// What the account was called last time anyone could ask.
    ///
    /// Carried so that an account which cannot be read is still recognisable. A
    /// row that says `claude/8817bc9b-c895-4ba4-a9c5` tells its reader to sign
    /// in somewhere without telling them where — and the identifier is the one
    /// thing about the account they have never seen.
    ///
    /// Empty when nothing is known, which is only true of an account nobody has
    /// ever signed into.
    public let lastKnownName: String

    public init(
        id: String, provider: ProviderID, handle: String, lastKnownName: String = ""
    ) {
        self.id = id
        self.provider = provider
        self.handle = handle
        self.lastKnownName = lastKnownName
    }
}

public protocol UsageProvider: Sendable {
    var id: ProviderID { get }

    /// Which accounts this provider can see at all.
    func discoverAccounts() async throws -> [AccountRef]

    /// A snapshot for one account. Throws `ProviderFailure`.
    func fetch(_ ref: AccountRef) async throws -> AccountSnapshot
}
