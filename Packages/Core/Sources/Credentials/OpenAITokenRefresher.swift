import Foundation
import ProviderKit
import CodexProvider

public struct OpenAITokenRefresher: TokenRefreshing {
    private let http: any HTTPClient

    public init(http: any HTTPClient = URLSessionHTTPClient()) { self.http = http }

    public func refresh(refreshToken: String) async throws -> RefreshedTokens {
        let (data, status) = try await http.post(
            CodexOAuthEndpoints.token, headers: CodexOAuthEndpoints.headers,
            body: CodexOAuthEndpoints.form([
                "grant_type": "refresh_token", "refresh_token": refreshToken,
                "client_id": CodexOAuthEndpoints.clientID,
            ]))
        if status == 400 || status == 401 {
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let error = root?["error"] as? String
                ?? (root?["error"] as? [String: Any])?["code"] as? String
            if let error, ["invalid_grant", "refresh_token_expired", "refresh_token_reused",
                           "refresh_token_invalid"].contains(error) {
                throw RefreshRejected()
            }
        }
        guard status == 200 else {
            throw ProviderFailure(kind: .network, diagnostic: "codex refresh failed, HTTP \(status)")
        }
        return try CodexOAuthEndpoints.tokens(from: data)
    }
}
