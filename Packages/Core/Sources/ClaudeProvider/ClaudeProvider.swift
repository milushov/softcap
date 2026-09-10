import Foundation
import ProviderKit

/// Where the provider gets a token. The implementation lives in `Credentials`:
/// the active account is read from the CLI keychain, inactive ones are refreshed
/// from their own copy.
public protocol ClaudeTokenSource: Sendable {
    func accessToken(for handle: String) async throws -> String
}

public struct ClaudeUsageProvider: UsageProvider {
    public let id: ProviderID = .claude

    private let http: any HTTPClient
    private let tokens: any ClaudeTokenSource
    private let knownAccounts: [AccountRef]
    private let identities: ClaudeIdentityCache

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!

    public init(
        http: any HTTPClient = URLSessionHTTPClient(),
        tokens: any ClaudeTokenSource,
        knownAccounts: [AccountRef],
        identities: ClaudeIdentityCache = ClaudeIdentityCache()
    ) {
        self.http = http
        self.tokens = tokens
        self.knownAccounts = knownAccounts.filter { $0.provider == .claude }
        self.identities = identities
    }

    public func discoverAccounts() async throws -> [AccountRef] { knownAccounts }

    /// What to call an account before, or instead of, asking the service.
    ///
    /// The identifier is the last resort and true only of an account nobody has
    /// ever signed into. Every other row names the account the reader knows.
    private static func name(for ref: AccountRef) -> String {
        ref.lastKnownName.isEmpty ? ref.id : ref.lastKnownName
    }

    public func fetch(_ ref: AccountRef) async throws -> AccountSnapshot {
        let token: String
        do {
            token = try await tokens.accessToken(for: ref.handle)
        } catch {
            // The name it was last known by, not the identifier. This is the row
            // a person reads when an account has stopped working, and the row
            // that most needs to say which account it is about.
            return broken(ref, name: Self.name(for: ref), plan: "—",
                          failure: failure(from: error))
        }

        let headers = [
            "Authorization": "Bearer \(token)",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": OAuthEndpoints.userAgent,
        ]

        // The profile supplies name and plan. Fetched once and then remembered:
        // an address and a plan name change about never, while a poll runs as
        // often as once a minute. Until it answers, the name the account was
        // last known by stands in — a single failed request used to drop the row
        // to `claude/<uuid>`, which reads as a different account rather than the
        // same one with a hiccup.
        var name = Self.name(for: ref)
        var plan = "—"
        if let known = await identities.identity(for: ref.id) {
            name = known.displayName
            plan = known.planLabel
        } else if let (data, code) = try? await http.get(Self.profileURL, headers: headers),
                  code == 200,
                  let profile = try? ClaudeProfileResponse.parse(data) {
            name = profile.displayName
            plan = profile.planLabel
            await identities.remember(profile, for: ref.id)
        }

        do {
            let (data, code) = try await http.get(Self.usageURL, headers: headers)
            switch code {
            case 200:
                let windows = try ClaudeUsageResponse.windows(from: data)
                return AccountSnapshot(
                    id: ref.id, provider: .claude, displayName: name, planLabel: plan,
                    windows: windows, freshness: .live(Date()), failure: nil
                )
            case 401, 403:
                return broken(ref, name: name, plan: plan, failure: ProviderFailure(
                    kind: .needsLogin, diagnostic: "token unavailable"
                ))
            default:
                return broken(ref, name: name, plan: plan, failure: ProviderFailure(
                    kind: .network, diagnostic: "http \(code)"
                ))
            }
        } catch {
            return broken(ref, name: name, plan: plan, failure: failure(from: error))
        }
    }

    private func broken(
        _ ref: AccountRef, name: String, plan: String, failure: ProviderFailure
    ) -> AccountSnapshot {
        AccountSnapshot(
            id: ref.id, provider: .claude, displayName: name, planLabel: plan,
            windows: [], freshness: .live(Date()), failure: failure
        )
    }

    /// The error message is always ours: foreign text could smuggle in a token.
    private func failure(from error: any Error) -> ProviderFailure {
        if let known = error as? ProviderFailure { return known }
        return ProviderFailure(kind: .network, diagnostic: "fetch failed")
    }
}
