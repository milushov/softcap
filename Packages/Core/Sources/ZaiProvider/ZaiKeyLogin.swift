import Foundation
import ProviderKit

/// Signing in by handing over the coding-plan key.
///
/// The key is checked by using it: one read of the quota endpoint says both
/// whether it works and what the plan is called. There is no second request to
/// ask who the account belongs to, because this service does not answer that —
/// see `docs/DECISIONS.md` for what the row is called instead and what that
/// costs.
public struct ZaiKeyLogin: KeyAuthenticating {
    public let provider: ProviderID = .glm

    private let http: any HTTPClient

    public init(http: any HTTPClient = URLSessionHTTPClient()) { self.http = http }

    public func account(for key: String) async throws -> AuthenticatedAccount {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProviderFailure(kind: .needsLogin, diagnostic: "no key was given")
        }

        let (data, status) = try await http.get(
            ZaiEndpoints.usage, headers: ZaiEndpoints.headers(key: trimmed))

        guard status == 200 else {
            throw ProviderFailure(
                kind: status == 401 || status == 403 ? .needsLogin : .network,
                diagnostic: "key check came back HTTP \(status)")
        }

        // Parsed rather than merely fetched. A 200 whose body this app cannot
        // read is a key that will produce an unreadable row on every poll from
        // here on, and finding that out now — while somebody is looking at the
        // field they just typed into — is the whole point of checking at all.
        // `parse` is also what turns an in-band refusal into `needsLogin`.
        let usage = try ZaiQuotaResponse.parse(data)

        let identifier = handle(forKey: trimmed)
        return AuthenticatedAccount(
            account: AccountRef(
                id: "\(provider.rawValue)/\(identifier)",
                provider: provider,
                handle: identifier,
                // The plan level, which is all this service says about an
                // account. Two accounts on one plan therefore read alike; the
                // decision log carries that and why it was accepted.
                lastKnownName: usage.planLabel),
            // Static: handed over whole, never rotated, nothing to refresh
            // with. `ProviderID.rotatesCredentials` is what tells the store so.
            tokens: RefreshedTokens(accessToken: trimmed, refreshToken: nil))
    }
}
