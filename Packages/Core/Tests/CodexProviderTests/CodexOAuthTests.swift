import Testing
import Foundation
import ProviderKit
@testable import CodexProvider

private actor AuthHTTP: HTTPClient {
    var response: (Data, Int)
    private(set) var request: (URL, [String: String], Data)?
    init(_ response: (Data, Int)) { self.response = response }
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        Issue.record("Codex sign-in should not fetch an Anthropic profile")
        return (Data(), 500)
    }
    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
        request = (url, headers, body)
        return response
    }
}

private func jwt(_ claims: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: claims)
    return "h." + data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "") + ".s"
}

@Suite struct CodexBrowserAuthentication {
    @Test func authorizationCarriesPKCEStateAndSubscriptionScopes() throws {
        let login = CodexOAuthLogin()
        let pair = try #require(PKCEPair.generate())
        let url = login.authorizationURL(
            redirectURI: CodexOAuthEndpoints.redirectURI, pkce: pair, state: "attempt", manual: false)
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(url.host == "auth.openai.com")
        #expect(query["client_id"] == CodexOAuthEndpoints.clientID)
        #expect(query["code_challenge"] == pair.challenge)
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["state"] == "attempt")
        #expect(query["scope"] == "openid profile email offline_access")
        #expect(query["redirect_uri"] == CodexOAuthEndpoints.redirectURI)
        #expect(query["id_token_add_organizations"] == "true")
        #expect(query["codex_cli_simplified_flow"] == "true")
        #expect(!url.absoluteString.contains(pair.verifier))
        #expect(login.localRedirect(port: 1455) == CodexOAuthEndpoints.redirectURI)
        #expect(login.localRedirect(port: 0) == nil)
        #expect(login.localRedirect(port: 1456) == nil)
        #expect(login.manualRedirectURI == nil)
    }

    @Test func exchangesFormBodyAndUsesOpenAIIdentity() async throws {
        let id = try jwt(["email": "sam@example.com", "https://api.openai.com/auth": [
            "chatgpt_account_id": "account-one", "chatgpt_plan_type": "plus"]])
        let data = try JSONSerialization.data(withJSONObject: [
            "access_token": "access", "refresh_token": "refresh", "id_token": id,
            "expires_in": 3600,
        ])
        let http = AuthHTTP((data, 200))
        let result = try await CodexOAuthLogin(http: http).authenticate(
            code: "code+with &/?=", verifier: "verifier+&", redirectURI: CodexOAuthEndpoints.redirectURI,
            state: "attempt")
        #expect(result.account.id == "codex/account-one")
        #expect(result.account.provider == .codex)
        #expect(result.account.lastKnownName == "sam@example.com")
        #expect(result.tokens.expiresIn == 3600)
        let request = try #require(await http.request)
        #expect(request.0 == CodexOAuthEndpoints.token)
        #expect(request.1["Content-Type"] == "application/x-www-form-urlencoded")
        let body = String(decoding: request.2, as: UTF8.self)
        #expect(body.contains("code=code%2Bwith%20%26%2F%3F%3D"))
        #expect(body.contains("code_verifier=verifier%2B%26"))
        #expect(body.contains("grant_type=authorization_code"))
        #expect(!body.contains("state="))
    }

    @Test func expiryFallsBackToAccessClaimsNotIdentityToken() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let access = try jwt(["exp": now.timeIntervalSince1970 + 900])
        let data = try JSONSerialization.data(withJSONObject: ["access_token": access])
        #expect(try CodexOAuthEndpoints.tokens(from: data, now: now).expiresIn == 900)
        #expect(try CodexOAuthEndpoints.tokens(from: Data(#"{"access_token":"opaque"}"#.utf8)).expiresIn == nil)
    }

    @Test func missingIdentityNeverCreatesAnUnknownAccount() async throws {
        let id = try jwt(["name": "Sam"])
        let data = try JSONSerialization.data(withJSONObject: [
            "access_token": "access", "refresh_token": "refresh", "id_token": id,
        ])
        await #expect(throws: ProviderFailure.self) {
            try await CodexOAuthLogin(http: AuthHTTP((data, 200))).authenticate(
                code: "code", verifier: "verifier", redirectURI: CodexOAuthEndpoints.redirectURI, state: "state")
        }
    }

    @Test func failedExchangeDoesNotExposeServerBody() async throws {
        let http = AuthHTTP((Data("private-code-and-verifier".utf8), 500))
        do {
            _ = try await CodexOAuthLogin(http: http).authenticate(
                code: "private-code", verifier: "private-verifier",
                redirectURI: CodexOAuthEndpoints.redirectURI, state: "state")
            Issue.record("expected a failure")
        } catch let failure as ProviderFailure {
            #expect(failure.kind == .network)
            #expect(!failure.diagnostic.contains("private"))
        }
    }
}
