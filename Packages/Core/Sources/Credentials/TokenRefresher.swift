import Foundation
import ProviderKit
import ClaudeProvider

public protocol TokenRefreshing: Sendable {
    func refresh(refreshToken: String) async throws -> RefreshedTokens
}

/// Refreshing an Anthropic session. Endpoint and body shape verified on
/// 2026-08-30: a bogus token gets `400 invalid_grant`.
public struct AnthropicTokenRefresher: TokenRefreshing {
    private let http: any HTTPClient

    public init(http: any HTTPClient = URLSessionHTTPClient()) { self.http = http }

    public func refresh(refreshToken: String) async throws -> RefreshedTokens {
        let body = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": OAuthEndpoints.clientID,
        ])

        let (data, code) = try await http.post(
            OAuthEndpoints.token, headers: OAuthEndpoints.jsonHeaders, body: body
        )
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        // `invalid_grant` on 400 is the spec's way of saying this token is
        // finished: expired, revoked, or rotated away by whoever refreshed it
        // last. Asking again with the same token gets the same answer forever,
        // so the caller is told to stop keeping it rather than to try later.
        if code == 400, (root?["error"] as? String) == "invalid_grant" {
            throw RefreshRejected()
        }

        guard code == 200, let access = root?["access_token"] as? String else {
            throw ProviderFailure(kind: .needsLogin, diagnostic: "refresh failed, HTTP \(code)")
        }
        return RefreshedTokens(
            accessToken: access, refreshToken: root?["refresh_token"] as? String
        )
    }
}
