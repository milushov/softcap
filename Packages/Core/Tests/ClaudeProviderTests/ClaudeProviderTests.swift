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

/// The service answering 429 is not the network being down: the row said
/// "Network unavailable" for hours on a machine that was online, about an
/// account whose sign-in was fine.
@Test func reportsRateLimitOn429() async throws {
    let http = StubHTTP(byPath: [
        "/api/oauth/profile": (profileBody, 200),
        "/api/oauth/usage": (d("{}"), 429),
    ])
    let ref = AccountRef(id: "claude/u-1", provider: .claude, handle: "u-1")
    let snapshot = try await provider(http).fetch(ref)
    #expect(snapshot.failure?.kind == .rateLimited)
    #expect(snapshot.failure?.diagnostic == "http 429")
}

/// A plan that ran out answers the usage request with the same 429 as a rate
/// limit. The profile is asked again — the remembered one still names the old
/// plan — and it is the profile that says which of the two it is.
@Test func reportsALapsedSubscriptionRatherThanARateLimit() async throws {
    let lapsed = d("""
    {"account":{"uuid":"u-1","email":"a@b.c","has_claude_max":false,"has_claude_pro":false},
     "organization":{"rate_limit_tier":"default_claude_max_20x","subscription_status":"canceled"}}
    """)
    let identities = ClaudeIdentityCache()
    await identities.remember(
        ClaudeProfile(uuid: "u-1", displayName: "a@b.c", planLabel: "Max 20x"), for: "claude/u-1")
    let http = StubHTTP(byPath: [
        "/api/oauth/profile": (lapsed, 200),
        "/api/oauth/usage": (d("{}"), 429),
    ])
    let subject = ClaudeUsageProvider(
        http: http, tokens: StubTokens(),
        knownAccounts: [AccountRef(id: "claude/u-1", provider: .claude, handle: "u-1")],
        identities: identities)
    let snapshot = try await subject.fetch(
        AccountRef(id: "claude/u-1", provider: .claude, handle: "u-1"))

    #expect(snapshot.failure?.kind == .noSubscription)
    #expect(snapshot.planLabel == "—")
    #expect(await identities.identity(for: "claude/u-1") == nil)
}
