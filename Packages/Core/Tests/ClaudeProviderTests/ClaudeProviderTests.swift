import Testing
import Foundation
import ProviderKit
@testable import ClaudeProvider

private struct StubHTTP: HTTPClient {
    let byPath: [String: (Data, Int)]

    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        guard headers["Authorization"]?.hasPrefix("Bearer ") == true else {
            Issue.record("the request went out with no token")
            return (Data(), 401)
        }
        return byPath[url.path] ?? (Data(), 404)
    }

    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
        byPath[url.path] ?? (Data(), 404)
    }
}

private struct StubTokens: ClaudeTokenSource {
    var token: String? = "SECRET-ACCESS-VALUE"
    func accessToken(for handle: String) async throws -> String {
        guard let token else {
            throw ProviderFailure(kind: .needsLogin, diagnostic: "sign-in required")
        }
        return token
    }
}

private func d(_ s: String) -> Data { s.data(using: .utf8)! }

private let profileBody = d("""
{"account":{"uuid":"u-1","email":"a@b.c"},"organization":{"rate_limit_tier":"default_claude_max_20x"}}
""")

private let usageBody = d("""
{"limits":[
  {"kind":"session","percent":5,"resets_at":"2026-08-30T14:00:00.277644+00:00","scope":null},
  {"kind":"weekly_all","percent":23,"resets_at":"2026-09-05T10:00:00.277667+00:00","scope":null}]}
""")

private func provider(_ http: StubHTTP, tokens: StubTokens = StubTokens()) -> ClaudeUsageProvider {
    ClaudeUsageProvider(
        http: http, tokens: tokens,
        knownAccounts: [AccountRef(id: "claude/u-1", provider: .claude, handle: "u-1")]
    )
}

@Test func buildsLiveSnapshot() async throws {
    let http = StubHTTP(byPath: [
        "/api/oauth/profile": (profileBody, 200),
        "/api/oauth/usage": (usageBody, 200),
    ])
    let subject = provider(http)
    let ref = try await subject.discoverAccounts()[0]
    let snapshot = try await subject.fetch(ref)

    #expect(snapshot.displayName == "a@b.c")
    #expect(snapshot.planLabel == "Max 20x")
    #expect(snapshot.windows.count == 2)
    #expect(snapshot.windows[0].percent == 5)
    #expect(snapshot.windows[1].percent == 23)
    #expect(snapshot.failure == nil)
    #expect(snapshot.freshness.isStale == false)
}

@Test func reportsNeedsLoginOn401() async throws {
    let http = StubHTTP(byPath: [
        "/api/oauth/profile": (profileBody, 200),
        "/api/oauth/usage": (d("{}"), 401),
    ])
    let ref = AccountRef(id: "claude/u-1", provider: .claude, handle: "u-1")
    let snapshot = try await provider(http).fetch(ref)

    #expect(snapshot.failure?.kind == .needsLogin)
    #expect(snapshot.windows.isEmpty)
}

@Test func reportsNetworkFailureOn500() async throws {
    let http = StubHTTP(byPath: [
        "/api/oauth/profile": (profileBody, 200),
        "/api/oauth/usage": (d("{}"), 500),
    ])
    let ref = AccountRef(id: "claude/u-1", provider: .claude, handle: "u-1")
    let snapshot = try await provider(http).fetch(ref)
    #expect(snapshot.failure?.kind == .network)
}

@Test func reportsNeedsLoginWhenTokenIsGone() async throws {
    let http = StubHTTP(byPath: [:])
    let ref = AccountRef(id: "claude/u-1", provider: .claude, handle: "u-1")
    let snapshot = try await provider(http, tokens: StubTokens(token: nil)).fetch(ref)

    #expect(snapshot.failure?.kind == .needsLogin)
    #expect(snapshot.displayName == "claude/u-1")   // there is nowhere to take a name from
}

@Test func neverPutsTokenIntoFailureMessage() async throws {
    let http = StubHTTP(byPath: [
        "/api/oauth/profile": (profileBody, 200),
        "/api/oauth/usage": (d("{}"), 401),
    ])
    let ref = AccountRef(id: "claude/u-1", provider: .claude, handle: "u-1")
    let snapshot = try await provider(http).fetch(ref)
    #expect(snapshot.failure?.diagnostic.contains("SECRET") == false)
}
