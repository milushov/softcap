import Foundation
import ProviderKit

/// Reads the plan and its two windows for accounts holding a coding-plan key.
///
/// The key is static: reading a quota with it rotates nothing and can sign
/// nothing out, which is why a key the person hands over is admissible here
/// where a refresh token copied from a CLI is not. `docs/authentication.md`
/// carries the distinction.
public struct ZaiUsageProvider: UsageProvider {
    public let id: ProviderID = .glm
    public static let usageURL = ZaiEndpoints.usage

    private let http: any HTTPClient
    private let tokens: any AccountTokenSource
    private let accounts: [AccountRef]
    private let now: @Sendable () -> Date

    public init(
        tokens: any AccountTokenSource, knownAccounts: [AccountRef],
        http: any HTTPClient = URLSessionHTTPClient(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.tokens = tokens
        self.accounts = knownAccounts.filter { $0.provider == .glm }
        self.http = http
        self.now = now
    }

    public func discoverAccounts() async throws -> [AccountRef] { accounts }

    public func fetch(_ ref: AccountRef) async throws -> AccountSnapshot {
        do {
            guard accounts.contains(where: { $0.id == ref.id }), ref.provider == .glm else {
                throw ProviderFailure(kind: .needsLogin, diagnostic: "unknown glm account")
            }

            let key = try await tokens.accessToken(for: ref)
            var answer = try await request(key: key)
            // One retry, and only if something actually replaced the key. This
            // service does not rotate, so the store keeps the credential rather
            // than discarding it over one status — asking again returns the
            // same string, and sending it twice would buy a second 401.
            if answer.1 == 401 {
                await tokens.invalidateAccessToken(for: ref, rejectedToken: key)
                let replacement = try await tokens.accessToken(for: ref)
                if replacement != key {
                    answer = try await request(key: replacement)
                }
            }

            guard answer.1 == 200 else {
                throw ProviderFailure(
                    kind: answer.1 == 401 || answer.1 == 403 ? .needsLogin : .network,
                    diagnostic: "glm usage failed, HTTP \(answer.1)")
            }

            let usage = try ZaiQuotaResponse.parse(answer.0)
            return snapshot(ref, plan: usage.planLabel, windows: usage.windows)
        } catch {
            return snapshot(ref, failure: error as? ProviderFailure
                ?? ProviderFailure(kind: .network, diagnostic: "glm usage request failed"))
        }
    }

    private func request(key: String) async throws -> (Data, Int) {
        try await http.get(ZaiEndpoints.usage, headers: ZaiEndpoints.headers(key: key))
    }

    private func snapshot(
        _ ref: AccountRef, plan: String = "—", windows: [LimitWindow] = [],
        failure: ProviderFailure? = nil
    ) -> AccountSnapshot {
        AccountSnapshot(
            id: ref.id,
            provider: .glm,
            displayName: ref.lastKnownName.isEmpty ? ref.id : ref.lastKnownName,
            planLabel: plan,
            windows: windows,
            freshness: .live(now()),
            failure: failure)
    }
}
