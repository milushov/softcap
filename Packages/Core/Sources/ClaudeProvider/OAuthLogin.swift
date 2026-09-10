import Foundation
import ProviderKit

public struct OAuthLogin: BrowserAuthenticating {
    public let provider: ProviderID = .claude
    public let callbackPath = "/callback"
    public let callbackPort: UInt16? = nil
    public var manualRedirectURI: String? { OAuthEndpoints.manualRedirect }
    private let http: any HTTPClient

    public init(http: any HTTPClient = URLSessionHTTPClient()) { self.http = http }

    /// The sign-in page URL.
    ///
    /// `manual: true` adds `code=true`, which makes the server display the code
    /// on the page instead of returning to `redirect_uri`. That is the fallback
    /// for when the localhost return does not work.
    public func authorizationURL(
        redirectURI: String, pkce: PKCEPair, state: String, manual: Bool
    ) -> URL {
        var components = URLComponents(
            url: OAuthEndpoints.authorize, resolvingAgainstBaseURL: false
        )!
        var items = [
            URLQueryItem(name: "client_id", value: OAuthEndpoints.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: OAuthEndpoints.scope),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        if manual { items.insert(URLQueryItem(name: "code", value: "true"), at: 0) }
        components.queryItems = items
        return components.url!
    }

    /// `state` is sent in the body as well as the query, because that is what
    /// the service is given by the client this app borrows its identity from —
    /// Claude Code posts `grant_type, code, redirect_uri, client_id,
    /// code_verifier, state`. Leaving it out is a difference from a request
    /// known to work, which is not a difference worth keeping.
    public func exchange(
        code: String, verifier: String, redirectURI: String, state: String
    ) async throws -> RefreshedTokens {
        let body = try JSONSerialization.data(withJSONObject: [
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
            "client_id": OAuthEndpoints.clientID,
            "redirect_uri": redirectURI,
            "state": state,
        ])

        let (data, status) = try await http.post(
            OAuthEndpoints.token, headers: OAuthEndpoints.jsonHeaders, body: body
        )
        guard status == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = root["access_token"] as? String
        else {
            // The body is not repeated outward: it may carry the code or the
            // verifier, and this message reaches the interface. The status is
            // safe and is the one thing worth knowing.
            throw ProviderFailure(
                kind: .needsLogin, diagnostic: "code exchange failed, HTTP \(status)")
        }
        return RefreshedTokens(
            accessToken: access, refreshToken: root["refresh_token"] as? String,
            expiresIn: (root["expires_in"] as? NSNumber)?.doubleValue
        )
    }

    public func authenticate(
        code: String, verifier: String, redirectURI: String, state: String
    ) async throws -> AuthenticatedAccount {
        let tokens = try await exchange(
            code: code, verifier: verifier, redirectURI: redirectURI, state: state)
        let (data, status) = try await http.get(
            URL(string: "https://api.anthropic.com/api/oauth/profile")!, headers: [
                "Authorization": "Bearer \(tokens.accessToken)",
                "anthropic-beta": "oauth-2025-04-20",
                "User-Agent": OAuthEndpoints.userAgent,
            ])
        guard status == 200 else {
            throw ProviderFailure(kind: .needsLogin, diagnostic: "profile read failed, HTTP \(status)")
        }
        let profile = try ClaudeProfileResponse.parse(data)
        return AuthenticatedAccount(account: AccountRef(
            id: "claude/\(profile.uuid)", provider: .claude, handle: profile.uuid,
            lastKnownName: profile.displayName), tokens: tokens)
    }
}
