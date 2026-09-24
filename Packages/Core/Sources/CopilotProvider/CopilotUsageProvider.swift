import Foundation
import ProviderKit

/// Reads the plan and what is left of its allowances, for accounts holding this
/// app's own device grant. Nothing is imported from any CLI, here as everywhere.
public struct CopilotUsageProvider: UsageProvider {
    public let id: ProviderID = .copilot
    public static let usageURL = CopilotEndpoints.usage

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
        self.accounts = knownAccounts.filter { $0.provider == .copilot }
        self.http = http
        self.now = now
    }

    public func discoverAccounts() async throws -> [AccountRef] { accounts }

    public func fetch(_ ref: AccountRef) async throws -> AccountSnapshot {
        do {
            guard accounts.contains(where: { $0.id == ref.id }), ref.provider == .copilot else {
                throw ProviderFailure(kind: .needsLogin, diagnostic: "unknown copilot account")
            }

            let access = try await tokens.accessToken(for: ref)
            var answer = try await request(access: access)
            // A token revoked between the poll starting and the request landing
            // invalidates only the copy this request used, and the retry is
            // worth making with whatever replaces it.
            //
            // Only if something does replace it. For a service that does not
            // rotate, the store keeps the grant rather than discarding it over
            // one status — so asking again returns the same string, and sending
            // it a second time would buy a second 401. The comparison is what
            // keeps the retry honest here and unchanged for Claude and Codex.
            if answer.1 == 401 {
                await tokens.invalidateAccessToken(for: ref, rejectedToken: access)
                let replacement = try await tokens.accessToken(for: ref)
                if replacement != access {
                    answer = try await request(access: replacement)
                }
            }

            guard answer.1 == 200 else {
                throw ProviderFailure(
                    kind: answer.1 == 401 || answer.1 == 403 ? .needsLogin : .network,
                    diagnostic: "copilot usage failed, HTTP \(answer.1)")
            }

            let usage = try CopilotQuotaResponse.parse(answer.0)
            return snapshot(ref, plan: usage.planLabel, windows: usage.windows)
        } catch {
            return snapshot(ref, failure: error as? ProviderFailure
                ?? ProviderFailure(kind: .network, diagnostic: "copilot usage request failed"))
        }
    }

    private func request(access: String) async throws -> (Data, Int) {
        try await http.get(
            CopilotEndpoints.usage, headers: CopilotEndpoints.apiHeaders(token: access))
    }

    /// A row with no windows is a real answer here, not an empty one.
    ///
    /// On a plan where every allowance is unlimited there is nothing to draw,
    /// and the row says who the account is and what the plan is called — which
    /// is true, and is the whole of what the service reported. The rule that a
    /// missing window is a failure rather than zero usage is about a window we
    /// could not read; a service saying there is no limit is a different
    /// sentence, and `parse` still refuses a reply it cannot understand.
    private func snapshot(
        _ ref: AccountRef, plan: String = "—", windows: [LimitWindow] = [],
        failure: ProviderFailure? = nil
    ) -> AccountSnapshot {
        AccountSnapshot(
            id: ref.id,
            provider: .copilot,
            displayName: ref.lastKnownName.isEmpty ? ref.id : ref.lastKnownName,
            planLabel: plan,
            windows: windows,
            freshness: .live(now()),
            failure: failure)
    }
}
