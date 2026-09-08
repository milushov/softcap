import Testing
import Foundation
import ProviderKit
@testable import ClaudeProvider

/// A box for the test: a `@Sendable` closure cannot write to a `var` directly.
private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?
    var value: Data? { lock.lock(); defer { lock.unlock() }; return stored }
    func set(_ data: Data) { lock.lock(); stored = data; lock.unlock() }
}

private struct LoginStubHTTP: HTTPClient {
    var response: (Data, Int)
    var seenBody: (@Sendable (Data) -> Void)?

    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        (Data(), 404)
    }
    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
        seenBody?(body)
        return response
    }
}

private func dd(_ s: String) -> Data { s.data(using: .utf8)! }

@Test func authorizationURLCarriesEveryRequiredParameter() throws {
    let login = OAuthLogin(http: LoginStubHTTP(response: (Data(), 200)))
    let pkce = try #require(PKCEPair.generate())
    let url = login.authorizationURL(
        redirectURI: "http://localhost:54545/callback", pkce: pkce,
        state: "st-1", manual: false
    )
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems ?? []
    let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

    // The subscription sign-in, not the API console: the console URL sends
    // people to "How will you use the Claude API?" instead.
    #expect(url.host == "claude.com")
    #expect(url.path == "/cai/oauth/authorize")
    #expect(byName["client_id"] == OAuthEndpoints.clientID)
    #expect(byName["response_type"] == "code")
    #expect(byName["redirect_uri"] == "http://localhost:54545/callback")
    #expect(byName["code_challenge"] == pkce.challenge)
    #expect(byName["code_challenge_method"] == "S256")
    #expect(byName["state"] == "st-1")
    #expect(byName["scope"] == OAuthEndpoints.scope)
    #expect(byName["code"] == nil)   // not the manual path
}

@Test func manualModeAddsCodeFlagAndItsOwnRedirect() throws {
    let login = OAuthLogin(http: LoginStubHTTP(response: (Data(), 200)))
    let url = login.authorizationURL(
        redirectURI: OAuthEndpoints.manualRedirect, pkce: try #require(PKCEPair.generate()),
        state: "st", manual: true
    )
    let byName = Dictionary(uniqueKeysWithValues:
        (URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
    #expect(byName["code"] == "true")
    #expect(byName["redirect_uri"] == OAuthEndpoints.manualRedirect)
}

@Test func exchangeReturnsBothTokens() async throws {
    let http = LoginStubHTTP(response: (dd(#"{"access_token":"at","refresh_token":"rt"}"#), 200))
    let tokens = try await OAuthLogin(http: http).exchange(
        code: "c", verifier: "v", redirectURI: "http://localhost:1/callback", state: "st")
    #expect(tokens.accessToken == "at")
    #expect(tokens.refreshToken == "rt")
}

@Test func exchangeSendsVerifierAndGrantType() async throws {
    let box = Box()
    let http = LoginStubHTTP(
        response: (dd(#"{"access_token":"at"}"#), 200),
        seenBody: { box.set($0) }
    )
    _ = try await OAuthLogin(http: http).exchange(
        code: "the-code", verifier: "the-verifier", redirectURI: "http://localhost:1/callback", state: "st")
    let sent = try #require(box.value)
    let json = try JSONSerialization.jsonObject(with: sent) as? [String: Any]
    #expect(json?["grant_type"] as? String == "authorization_code")
    #expect(json?["code"] as? String == "the-code")
    #expect(json?["code_verifier"] as? String == "the-verifier")
    #expect(json?["client_id"] as? String == OAuthEndpoints.clientID)
    #expect(json?["redirect_uri"] as? String == "http://localhost:1/callback")
    // Sent in the body as well as the query: the client whose identity this
    // app borrows sends it there, and the first sign-in attempt without it
    // came back as a failure with nothing to say why.
    #expect(json?["state"] as? String == "st")
}

@Test func serverErrorBecomesNeedsLogin() async {
    let http = LoginStubHTTP(response: (dd(#"{"error":"invalid_grant"}"#), 400))
    await #expect(throws: ProviderFailure.self) {
        _ = try await OAuthLogin(http: http).exchange(
            code: "c", verifier: "v", redirectURI: "http://localhost:1/callback", state: "st")
    }
}

@Test func errorMessageNeverLeaksTheVerifier() async {
    let http = LoginStubHTTP(response: (dd(#"{"error":"invalid_grant"}"#), 400))
    do {
        _ = try await OAuthLogin(http: http).exchange(
            code: "c", verifier: "SECRET-VERIFIER", redirectURI: "http://localhost:1/callback", state: "st")
        Issue.record("an error was expected")
    } catch let failure as ProviderFailure {
        #expect(failure.diagnostic.contains("SECRET") == false)
    } catch {
        Issue.record("a different kind of error")
    }
}

@Test func requestsOnlySubscriptionScopes() {
    let login = OAuthLogin(http: LoginStubHTTP(response: (Data(), 200)))
    let url = login.authorizationURL(
        redirectURI: "http://localhost:1/callback", pkce: try! #require(PKCEPair.generate()),
        state: "st", manual: false
    )
    let scope = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        .queryItems?.first { $0.name == "scope" }?.value ?? ""

    // The app reads usage and never creates API keys. Asking for a permission
    // it does not need would be wrong even if the server granted it.
    #expect(scope.contains("org:create_api_key") == false)
    #expect(scope.contains("user:profile"))
    #expect(scope.contains("user:sessions:claude_code"))
}
