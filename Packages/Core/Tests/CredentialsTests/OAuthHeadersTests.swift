import Testing
import Foundation
import ProviderKit
import ClaudeProvider
@testable import Credentials

/// Records the headers a call went out with.
private final class Headers: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: String] = [:]
    var value: [String: String] { lock.lock(); defer { lock.unlock() }; return stored }
    func set(_ h: [String: String]) { lock.lock(); stored = h; lock.unlock() }
}

private struct HeaderCapturingHTTP: HTTPClient {
    let seen: Headers
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        seen.set(headers)
        return (Data(#"{"access_token":"at"}"#.utf8), 200)
    }
    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
        seen.set(headers)
        return (Data(#"{"access_token":"at","refresh_token":"rt"}"#.utf8), 200)
    }
}

/// Both calls to the token endpoint must identify themselves.
///
/// Without a `User-Agent` the endpoint answers `403` with Cloudflare's
/// `error code: 1010` — a block on the caller, not an OAuth reply, which the app
/// then read as "sign-in required". The header was present on the profile and
/// usage reads and missing on exchange and refresh: the two that carry the whole
/// point of the app, signing in and keeping an inactive account alive.
@Suite struct OAuthCallsIdentifyThemselves {

    @Test func theTokenExchangeSendsAUserAgent() async throws {
        let seen = Headers()
        _ = try await OAuthLogin(http: HeaderCapturingHTTP(seen: seen)).exchange(
            code: "c", verifier: "v", redirectURI: "http://localhost:1/callback", state: "s")
        #expect(seen.value["User-Agent"] == OAuthEndpoints.userAgent)
        #expect(seen.value["Content-Type"] == "application/json")
    }

    @Test func theTokenRefreshSendsAUserAgent() async throws {
        let seen = Headers()
        _ = try await AnthropicTokenRefresher(http: HeaderCapturingHTTP(seen: seen))
            .refresh(refreshToken: "old")
        #expect(seen.value["User-Agent"] == OAuthEndpoints.userAgent)
        #expect(seen.value["Content-Type"] == "application/json")
    }

    /// The header names the client the sign-in was started under; a different
    /// spelling is a different caller.
    @Test func theUserAgentIsTheOneTheServiceKnows() {
        #expect(OAuthEndpoints.userAgent == "claude-cli/2.0.0 (external, cli)")
        #expect(OAuthEndpoints.jsonHeaders["User-Agent"] == OAuthEndpoints.userAgent)
    }
}
