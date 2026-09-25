import Foundation
import ProviderKit

/// Signing in by handing over a Kimi Code subscription key.
///
/// The key is checked by being used, and the same request settles the other
/// thing the key does not say: which of the two hosts it belongs to. Whichever
/// answers is written into the handle, so every poll afterwards asks one host
/// rather than both.
public struct KimiKeyLogin: KeyAuthenticating {
    public let provider: ProviderID = .kimi

    private let http: any HTTPClient
    private let accountName: String

    /// The name every row of this service carries.
    ///
    /// Supplied rather than written here: the reply says nothing about whose
    /// account it is or what plan it is on, so the name is the product's, and a
    /// product name is the app layer's to give. `ProviderID.title` is the only
    /// brand name Core is allowed, and it is the short caption rather than the
    /// name a person chose this service by.
    public init(
        http: any HTTPClient = URLSessionHTTPClient(),
        accountName: String = ProviderID.kimi.title
    ) {
        self.http = http
        self.accountName = accountName
    }

    public func account(for key: String) async throws -> AuthenticatedAccount {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProviderFailure(kind: .needsLogin, diagnostic: "no key was given")
        }

        var refusals: [ProviderFailure] = []

        for region in KimiEndpoints.Region.allCases {
            do {
                let (data, status) = try await http.get(
                    region.usage, headers: KimiEndpoints.headers(key: trimmed))

                guard status == 200 else {
                    refusals.append(ProviderFailure(
                        kind: status == 401 || status == 403 ? .needsLogin : .network,
                        diagnostic: "\(region.rawValue) came back HTTP \(status)"))
                    continue
                }

                // Parsed, not merely fetched: a 200 this app cannot read is a
                // key that would produce an unreadable row on every poll from
                // here on, and the moment to say so is while the person is
                // still looking at the field they typed into.
                _ = try KimiUsageResponse.parse(data)

                let named = KimiEndpoints.handle(region, handle(forKey: trimmed))
                return AuthenticatedAccount(
                    account: AccountRef(
                        id: "\(provider.rawValue)/\(named)",
                        provider: provider,
                        handle: named,
                        lastKnownName: accountName),
                    // Static: handed over whole, never rotated, nothing to
                    // refresh with.
                    tokens: RefreshedTokens(accessToken: trimmed, refreshToken: nil))
            } catch let failure as ProviderFailure {
                refusals.append(failure)
            }
        }

        // A host that was unreachable is not a key that is wrong, and neither is
        // a reply this app could not read. Telling somebody to find a new key
        // sends them after a credential that was never the problem — and for a
        // schema change it sends them after it forever, because the new key
        // fails in exactly the same way.
        //
        // So `needsLogin` is said only when every host actually refused the
        // credential. An unreadable reply anywhere is `malformed`, which is the
        // kind that says "this app could not read it" and offers nothing to do
        // about it; anything else left is the network. The first draft folded
        // `malformed` in with the refusals, which is the same mistake written
        // the other way round.
        let kinds = Set(refusals.map(\.kind))
        let kind: ProviderFailure.Kind =
            if refusals.isEmpty || kinds == [.needsLogin] { .needsLogin }
            else if kinds.contains(.malformed) { .malformed }
            else { .network }

        throw ProviderFailure(
            kind: kind,
            diagnostic: "no host took the key: "
                + refusals.map(\.diagnostic).joined(separator: "; "))
    }
}
