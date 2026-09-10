import Foundation
import ProviderKit

/// Fetches only accounts holding Softcap's own browser grant. Local CLI tokens
/// never reach this provider and are never refreshed on its behalf.
public struct CodexLiveUsageProvider: UsageProvider {
    public let id: ProviderID = .codex
    public static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private let http: any HTTPClient
    private let tokens: any AccountTokenSource
    private let accounts: [AccountRef]

    public init(
        tokens: any AccountTokenSource, knownAccounts: [AccountRef],
        http: any HTTPClient = URLSessionHTTPClient()
    ) {
        self.tokens = tokens
        self.accounts = knownAccounts.filter { $0.provider == .codex }
        self.http = http
    }

    public func discoverAccounts() async throws -> [AccountRef] { accounts }

    public func fetch(_ ref: AccountRef) async throws -> AccountSnapshot {
        do {
            guard accounts.contains(where: { $0.id == ref.id }), ref.provider == .codex else {
                throw ProviderFailure(kind: .needsLogin, diagnostic: "unknown codex account")
            }
            var access = try await tokens.accessToken(for: ref)
            var response = try await request(ref, access: access)
            // An early revocation invalidates only the access token that this
            // request used. One retry prevents an old cached token from making
            // a valid refresh grant look like a signed-out account forever.
            if response.1 == 401 {
                await tokens.invalidateAccessToken(for: ref, rejectedToken: access)
                access = try await tokens.accessToken(for: ref)
                response = try await request(ref, access: access)
            }
            guard response.1 == 200 else {
                throw ProviderFailure(
                    kind: response.1 == 401 || response.1 == 403 ? .needsLogin : .network,
                    diagnostic: "codex usage failed, HTTP \(response.1)")
            }
            let usage = try CodexUsageResponse.parse(response.0)
            return snapshot(ref, plan: usage.planType?.capitalized ?? "—", windows: usage.windows)
        } catch {
            return snapshot(ref, failure: error as? ProviderFailure
                ?? ProviderFailure(kind: .network, diagnostic: "codex usage request failed"))
        }
    }

    private func request(_ ref: AccountRef, access: String) async throws -> (Data, Int) {
        try await http.get(Self.usageURL, headers: [
            "Authorization": "Bearer \(access)",
            "ChatGPT-Account-Id": ref.handle,
            "Accept": "application/json",
        ])
    }

    private func snapshot(
        _ ref: AccountRef, plan: String = "—", windows: [LimitWindow] = [],
        failure: ProviderFailure? = nil
    ) -> AccountSnapshot {
        AccountSnapshot(
            id: ref.id, provider: .codex,
            displayName: ref.lastKnownName.isEmpty ? ref.handle : ref.lastKnownName,
            planLabel: plan, windows: windows, freshness: .live(Date()), failure: failure)
    }
}
