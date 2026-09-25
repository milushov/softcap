import Foundation
import ProviderKit

/// Reads a Kimi Code subscription's two windows for accounts holding a key.
///
/// The key is static, so this provider never rotates anything and the store
/// never refreshes on its behalf — the same footing as the GLM Coding Plan, and
/// `docs/authentication.md` carries why a key given by hand is admissible where
/// a token copied from a CLI is not.
public struct KimiUsageProvider: UsageProvider {
    public let id: ProviderID = .kimi

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
        self.accounts = knownAccounts.filter { $0.provider == .kimi }
        self.http = http
        self.now = now
    }

    public func discoverAccounts() async throws -> [AccountRef] { accounts }

    public func fetch(_ ref: AccountRef) async throws -> AccountSnapshot {
        do {
            guard accounts.contains(where: { $0.id == ref.id }), ref.provider == .kimi else {
                throw ProviderFailure(kind: .needsLogin, diagnostic: "unknown kimi account")
            }

            // The host this account's key belongs to, decided once at sign-in
            // and carried in the handle. Asking both every poll would be a
            // wasted request every five minutes for everybody on the second.
            let region = KimiEndpoints.region(ofHandle: ref.handle)

            let key = try await tokens.accessToken(for: ref)
            var answer = try await request(key: key, from: region)
            // One retry, and only if something replaced the key. This service
            // does not rotate, so the store keeps the credential rather than
            // discarding it over one status — asking again returns the same
            // string, and sending it twice would buy a second 401.
            if answer.1 == 401 {
                await tokens.invalidateAccessToken(for: ref, rejectedToken: key)
                let replacement = try await tokens.accessToken(for: ref)
                if replacement != key {
                    answer = try await request(key: replacement, from: region)
                }
            }

            guard answer.1 == 200 else {
                throw ProviderFailure(
                    kind: answer.1 == 401 || answer.1 == 403 ? .needsLogin : .network,
                    diagnostic: "kimi usage failed, HTTP \(answer.1)")
            }

            let usage = try KimiUsageResponse.parse(answer.0)
            return snapshot(ref, windows: usage.windows)
        } catch {
            return snapshot(ref, failure: error as? ProviderFailure
                ?? ProviderFailure(kind: .network, diagnostic: "kimi usage request failed"))
        }
    }

    private func request(key: String, from region: KimiEndpoints.Region) async throws -> (Data, Int) {
        try await http.get(region.usage, headers: KimiEndpoints.headers(key: key))
    }

    /// No plan label. The reply says what is left of the windows and not which
    /// plan they belong to, and a dash is what every other row without a plan
    /// already shows — inventing one from the window sizes would be a guess
    /// printed as a fact.
    private func snapshot(
        _ ref: AccountRef, windows: [LimitWindow] = [], failure: ProviderFailure? = nil
    ) -> AccountSnapshot {
        AccountSnapshot(
            id: ref.id,
            provider: .kimi,
            displayName: ref.lastKnownName.isEmpty ? ref.id : ref.lastKnownName,
            planLabel: "—",
            windows: windows,
            freshness: .live(now()),
            failure: failure)
    }
}
