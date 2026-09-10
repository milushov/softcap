import Foundation
import ProviderKit

/// Public Codex client configuration. Protocol constants were checked against
/// the installed CLI; see docs/authentication.md for the compatibility boundary.
public enum CodexOAuthEndpoints {
    public static let authorize = URL(string: "https://auth.openai.com/oauth/authorize")!
    public static let token = URL(string: "https://auth.openai.com/oauth/token")!
    public static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    public static let redirectURI = "http://localhost:1455/auth/callback"
    public static let scope = "openid profile email offline_access"
    public static let headers = ["Content-Type": "application/x-www-form-urlencoded"]

    public static func form(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let text = fields.sorted { $0.key < $1.key }.map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\(value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&")
        return Data(text.utf8)
    }

    public static func tokens(from data: Data, now: Date = Date()) throws -> RefreshedTokens {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = root["access_token"] as? String, !access.isEmpty else {
            throw ProviderFailure(kind: .malformed, diagnostic: "token response has no access token")
        }
        let expiry = (root["expires_in"] as? NSNumber)?.doubleValue
            ?? (JWTClaims.decode(access)?["exp"] as? NSNumber).map {
                $0.doubleValue - now.timeIntervalSince1970
            }
        return RefreshedTokens(
            accessToken: access, refreshToken: root["refresh_token"] as? String,
            expiresIn: expiry)
    }
}

public struct CodexOAuthLogin: BrowserAuthenticating {
    public let provider: ProviderID = .codex
    public let callbackPath = "/auth/callback"
    public let callbackPort: UInt16? = 1455
    // OpenAI does not offer Claude's paste-a-code redirect. A failed bind must
    // remain a visible, retryable error, never open a different redirect URI.
    public let manualRedirectURI: String? = nil
    private let http: any HTTPClient

    public init(http: any HTTPClient = URLSessionHTTPClient()) { self.http = http }

    public func authorizationURL(
        redirectURI: String, pkce: PKCEPair, state: String, manual: Bool
    ) -> URL {
        var parts = URLComponents(url: CodexOAuthEndpoints.authorize, resolvingAgainstBaseURL: false)!
        parts.queryItems = [
            URLQueryItem(name: "client_id", value: CodexOAuthEndpoints.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: CodexOAuthEndpoints.scope),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "originator", value: "codex_cli_rs"),
            URLQueryItem(name: "prompt", value: "login"),
        ]
        return parts.url!
    }

    public func authenticate(
        code: String, verifier: String, redirectURI: String, state: String
    ) async throws -> AuthenticatedAccount {
        guard redirectURI == CodexOAuthEndpoints.redirectURI else {
            throw ProviderFailure(kind: .malformed, diagnostic: "unsupported codex redirect")
        }
        let (data, status) = try await http.post(
            CodexOAuthEndpoints.token, headers: CodexOAuthEndpoints.headers,
            body: CodexOAuthEndpoints.form([
                "grant_type": "authorization_code", "code": code,
                "client_id": CodexOAuthEndpoints.clientID,
                "redirect_uri": redirectURI, "code_verifier": verifier,
            ]))
        guard status == 200 else {
            throw ProviderFailure(
                kind: status >= 500 || status == 429 ? .network : .needsLogin,
                diagnostic: "codex code exchange failed, HTTP \(status)")
        }
        let tokens = try CodexOAuthEndpoints.tokens(from: data)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let idToken = root?["id_token"] as? String else {
            throw ProviderFailure(kind: .malformed, diagnostic: "codex sign-in has no identity")
        }
        let identity = try CodexIdentityReader.parse(idToken: idToken)
        return AuthenticatedAccount(account: AccountRef(
            id: "codex/\(identity.accountID)", provider: .codex,
            handle: identity.accountID, lastKnownName: identity.displayName), tokens: tokens)
    }
}
