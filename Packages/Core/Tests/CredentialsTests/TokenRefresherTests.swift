import Testing
import Foundation
import ProviderKit
import ClaudeProvider
@testable import Credentials

/// Captures the request body so the test can assert on what was sent.
private final class Sent: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: (url: URL, body: Data)?
    var value: (url: URL, body: Data)? { lock.lock(); defer { lock.unlock() }; return stored }
    func set(_ url: URL, _ body: Data) { lock.lock(); stored = (url, body); lock.unlock() }
}

private struct RefreshStubHTTP: HTTPClient {
    var response: (Data, Int)
    var sent: Sent?

    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        (Data(), 404)
    }
    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
        sent?.set(url, body)
        return response
    }
}

private func d(_ s: String) -> Data { s.data(using: .utf8)! }

@Suite struct TokenRefreshing_ {

    @Test func returnsBothTokens() async throws {
        let http = RefreshStubHTTP(
            response: (d(#"{"access_token":"at","refresh_token":"rt"}"#), 200)
        )
        let tokens = try await AnthropicTokenRefresher(http: http).refresh(refreshToken: "old")
        #expect(tokens.accessToken == "at")
        #expect(tokens.refreshToken == "rt")
    }

    /// The server may keep the old refresh token instead of rotating it. That is
    /// valid: the caller keeps using the one it has.
    @Test func missingRotatedTokenIsNotAnError() async throws {
        let http = RefreshStubHTTP(response: (d(#"{"access_token":"at"}"#), 200))
        let tokens = try await AnthropicTokenRefresher(http: http).refresh(refreshToken: "old")
        #expect(tokens.accessToken == "at")
        #expect(tokens.refreshToken == nil)
    }

    @Test func sendsGrantTypeAndClientToTheCurrentEndpoint() async throws {
        let sent = Sent()
        let http = RefreshStubHTTP(
            response: (d(#"{"access_token":"at"}"#), 200), sent: sent
        )
        _ = try await AnthropicTokenRefresher(http: http).refresh(refreshToken: "the-old-token")

        let request = try #require(sent.value)
        // The domain moved from claude.ai; a regression here would silently
        // break refreshing for every non-active account.
        #expect(request.url == OAuthEndpoints.token)

        let json = try JSONSerialization.jsonObject(with: request.body) as? [String: Any]
        #expect(json?["grant_type"] as? String == "refresh_token")
        #expect(json?["refresh_token"] as? String == "the-old-token")
        #expect(json?["client_id"] as? String == OAuthEndpoints.clientID)
    }

    /// A refusal that is not `invalid_grant` stays an ordinary failure — the
    /// token may well still be good and the next poll is worth making. Only
    /// `invalid_grant` is final, and that has its own suite below.
    @Test func otherRefusalsMeanSignInNeededWithoutBeingFinal() async {
        let http = RefreshStubHTTP(response: (d(#"{"error":"invalid_client"}"#), 401))
        await #expect(throws: ProviderFailure.self) {
            _ = try await AnthropicTokenRefresher(http: http).refresh(refreshToken: "dead")
        }
    }

    @Test func responseWithoutAccessTokenIsRejected() async {
        // A 200 with an unexpected body must not be taken as success.
        let http = RefreshStubHTTP(response: (d(#"{"ok":true}"#), 200))
        await #expect(throws: ProviderFailure.self) {
            _ = try await AnthropicTokenRefresher(http: http).refresh(refreshToken: "x")
        }
    }

    /// Checked on both paths a refusal can take. The token is the one thing in
    /// this call worth never writing down, and it would be easy to put it in a
    /// message while explaining why it did not work.
    @Test func noErrorEchoesTheToken() async {
        for (payload, code) in [(#"{"error":"invalid_grant"}"#, 400),
                                (#"{"error":"invalid_client"}"#, 401),
                                ("not json", 500)] {
            let http = RefreshStubHTTP(response: (d(payload), code))
            do {
                _ = try await AnthropicTokenRefresher(http: http)
                    .refresh(refreshToken: "SECRET-REFRESH-VALUE")
                Issue.record("HTTP \(code) did not fail at all")
            } catch let failure as ProviderFailure {
                #expect(!failure.diagnostic.contains("SECRET"), "leaked in \(failure.diagnostic)")
            } catch is RefreshRejected {
                // Carries no message of its own, so there is nothing to leak.
            } catch {
                Issue.record("HTTP \(code) threw \(type(of: error))")
            }
        }
    }
}

/// `invalid_grant` on 400 is the spec's way of saying a refresh token is
/// finished. Asking again with the same token gets the same answer forever, so
/// the store stops keeping it — a client that retries a credential it has been
/// told is dead, every five minutes, indefinitely, is a badly behaved one.
@Suite struct ARejectedTokenIsNotKept {

    private func body(_ json: String) -> Data { Data(json.utf8) }

    @Test func invalidGrantIsItsOwnAnswer() async {
        let http = RefreshStubHTTP(
            response: (Data(#"{"error":"invalid_grant"}"#.utf8), 400)
        )
        await #expect(throws: RefreshRejected.self) {
            _ = try await AnthropicTokenRefresher(http: http).refresh(refreshToken: "old")
        }
    }

    /// A 400 that is not about the grant, and any other status, stays an
    /// ordinary failure: those are worth trying again in five minutes.
    @Test func otherFailuresAreOrdinary() async {
        for (payload, code) in [(#"{"error":"invalid_request"}"#, 400),
                                (#"{"error":"server_error"}"#, 500),
                                ("not json", 503)] {
            let http = RefreshStubHTTP(response: (Data(payload.utf8), code))
            do {
                _ = try await AnthropicTokenRefresher(http: http).refresh(refreshToken: "old")
                Issue.record("HTTP \(code) did not fail at all")
            } catch is RefreshRejected {
                Issue.record("HTTP \(code) with \(payload) was treated as final")
            } catch {
                // an ordinary ProviderFailure, which is what these are
            }
        }
    }

    @Test func aSuccessfulRefreshIsUnaffected() async throws {
        let http = RefreshStubHTTP(
            response: (Data(#"{"access_token":"at","refresh_token":"rt"}"#.utf8), 200)
        )
        let tokens = try await AnthropicTokenRefresher(http: http).refresh(refreshToken: "old")
        #expect(tokens.accessToken == "at")
    }
}
