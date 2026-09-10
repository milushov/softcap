import Testing
import Foundation
import ProviderKit
import CodexProvider
@testable import Credentials

private actor RefreshHTTP: HTTPClient {
    let reply: (Data, Int)
    private(set) var body: Data?
    init(_ body: String, status: Int) { reply = (Data(body.utf8), status) }
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        Issue.record("refresh must POST")
        return reply
    }
    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
        #expect(url == CodexOAuthEndpoints.token)
        #expect(headers["Content-Type"] == "application/x-www-form-urlencoded")
        #expect(headers["anthropic-beta"] == nil)
        self.body = body
        return reply
    }
}

@Suite struct OpenAIRefreshProtocol {
    @Test func receivesRotationAndPostsEscapedForm() async throws {
        let http = RefreshHTTP(#"{"access_token":"access","refresh_token":"rotated","expires_in":3600}"#, status: 200)
        let result = try await OpenAITokenRefresher(http: http).refresh(refreshToken: "a+b&c")
        #expect(result.accessToken == "access")
        #expect(result.refreshToken == "rotated")
        #expect(result.expiresIn == 3600)
        let body = String(decoding: try #require(await http.body), as: UTF8.self)
        #expect(body.contains("refresh_token=a%2Bb%26c"))
        #expect(body.contains("grant_type=refresh_token"))
        #expect(body.contains("client_id=" + CodexOAuthEndpoints.clientID))
    }

    @Test(arguments: ["invalid_grant", "refresh_token_expired", "refresh_token_reused", "refresh_token_invalid"])
    func permanentRejectionsAreExplicit(code: String) async {
        let http = RefreshHTTP("{\"error\":{\"code\":\"\(code)\"}}", status: 401)
        await #expect(throws: RefreshRejected.self) {
            try await OpenAITokenRefresher(http: http).refresh(refreshToken: "old")
        }
        let flat = RefreshHTTP("{\"error\":\"\(code)\"}", status: 400)
        await #expect(throws: RefreshRejected.self) {
            try await OpenAITokenRefresher(http: flat).refresh(refreshToken: "old")
        }
    }

    @Test(arguments: [429, 500, 503]) func transientFailuresKeepTheGrant(status: Int) async throws {
        let http = RefreshHTTP("service unavailable", status: status)
        do {
            _ = try await OpenAITokenRefresher(http: http).refresh(refreshToken: "held")
            Issue.record("expected failure")
        } catch let failure as ProviderFailure {
            #expect(failure.kind == .network)
        }
    }
}
