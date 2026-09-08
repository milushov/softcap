import Testing
import Foundation
import ProviderKit
@testable import ClaudeProvider

/// A poll runs as often as once a minute and used to ask the profile endpoint
/// every time — for an address and a plan name that change about never.
@Suite struct RememberingWhatAnAccountIsCalled {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func profile(_ name: String, _ plan: String = "Max 20x") -> ClaudeProfile {
        ClaudeProfile(uuid: "u", displayName: name, planLabel: plan)
    }

    @Test func nothingIsKnownAtFirst() async {
        let cache = ClaudeIdentityCache()
        #expect(await cache.identity(for: "claude/a") == nil)
    }

    @Test func aRememberedNameComesBack() async {
        let cache = ClaudeIdentityCache()
        await cache.remember(profile("sam@example.com"), for: "claude/a")
        let known = await cache.identity(for: "claude/a")
        #expect(known?.displayName == "sam@example.com")
        #expect(known?.planLabel == "Max 20x")
    }

    @Test func accountsAreKeptApart() async {
        let cache = ClaudeIdentityCache()
        await cache.remember(profile("sam@example.com"), for: "claude/a")
        #expect(await cache.identity(for: "claude/b") == nil)
    }

    /// A plan can be upgraded, so the entry is not kept for good.
    @Test func anEntryExpires() async {
        nonisolated(unsafe) var now = start
        let cache = ClaudeIdentityCache(lifetime: 3600, now: { now })
        await cache.remember(profile("sam@example.com"), for: "claude/a")

        now = start.addingTimeInterval(3599)
        #expect(await cache.identity(for: "claude/a") != nil, "expired too early")

        now = start.addingTimeInterval(3601)
        #expect(await cache.identity(for: "claude/a") == nil, "never expired")
    }

    @Test func rememberingAgainRestartsTheClock() async {
        nonisolated(unsafe) var now = start
        let cache = ClaudeIdentityCache(lifetime: 3600, now: { now })
        await cache.remember(profile("old@example.com"), for: "claude/a")

        now = start.addingTimeInterval(3000)
        await cache.remember(profile("new@example.com"), for: "claude/a")

        now = start.addingTimeInterval(5000)
        #expect(await cache.identity(for: "claude/a")?.displayName == "new@example.com")
    }

    /// Forgetting an account should forget what it was called.
    @Test func forgettingClearsTheEntry() async {
        let cache = ClaudeIdentityCache()
        await cache.remember(profile("sam@example.com"), for: "claude/a")
        await cache.forget("claude/a")
        #expect(await cache.identity(for: "claude/a") == nil)
    }
}

/// Counts what a poll actually asks the network for.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    func add(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
    var paths: [String] { lock.lock(); defer { lock.unlock() }; return urls.map(\.path) }
}

private struct CountingHTTP: HTTPClient {
    let counter: Counter
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        counter.add(url)
        if url.path.hasSuffix("profile") {
            let body = #"{"account":{"uuid":"u","email":"sam@example.com"},"# +
                       #""organization":{"rate_limit_tier":"default_claude_max_20x"}}"#
            return (Data(body.utf8), 200)
        }
        return (Data(#"{"limits":[{"kind":"session","percent":10,"resets_at":null}]}"#.utf8), 200)
    }
    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
        (Data(), 404)
    }
}

private struct FixedToken: ClaudeTokenSource {
    func accessToken(for handle: String) async throws -> String { "t" }
}

@Suite struct PollingDoesNotReAskWhatItKnows {

    private var ref: AccountRef {
        AccountRef(id: "claude/a", provider: .claude, handle: "h")
    }

    @Test func theProfileIsFetchedOnceAndThenRemembered() async throws {
        let counter = Counter()
        let cache = ClaudeIdentityCache()
        let provider = ClaudeUsageProvider(
            http: CountingHTTP(counter: counter), tokens: FixedToken(),
            knownAccounts: [ref], identities: cache
        )

        _ = try await provider.fetch(ref)
        _ = try await provider.fetch(ref)
        _ = try await provider.fetch(ref)

        let profileCalls = counter.paths.filter { $0.hasSuffix("profile") }.count
        let usageCalls = counter.paths.filter { $0.hasSuffix("usage") }.count
        #expect(profileCalls == 1, "asked for the profile \(profileCalls) times")
        #expect(usageCalls == 3, "usage must still be read every poll")
    }

    /// The name has to survive across polls, not merely be fetched less.
    @Test func theNameSurvivesLaterPolls() async throws {
        let cache = ClaudeIdentityCache()
        let provider = ClaudeUsageProvider(
            http: CountingHTTP(counter: Counter()), tokens: FixedToken(),
            knownAccounts: [ref], identities: cache
        )
        _ = try await provider.fetch(ref)
        let second = try await provider.fetch(ref)
        #expect(second.displayName == "sam@example.com")
        #expect(second.planLabel == "Max 20x")
    }
}

/// An account that cannot be read is still one the reader has to recognise. A row
/// showing `claude/` and a UUID tells them to sign in somewhere without telling
/// them where — and the identifier is the one thing about the account they have
/// never seen.
///
/// The example is written that way on purpose: pasting the real one from this
/// machine is what the repository's personal-data check exists to stop, and it
/// stopped exactly that here.
@Suite struct NamingAnAccountThatCannotBeRead {

    private struct FailingHTTP: HTTPClient {
        func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
            (Data(), 500)
        }
        func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
            (Data(), 500)
        }
    }

    private struct FixedToken: ClaudeTokenSource {
        func accessToken(for handle: String) async throws -> String { "t" }
    }

    @Test func theStoredNameIsUsedWhenTheProfileCannotBeRead() async throws {
        let ref = AccountRef(id: "claude/u-1", provider: .claude, handle: "u-1",
                             lastKnownName: "sam@example.com")
        let provider = ClaudeUsageProvider(
            http: FailingHTTP(), tokens: FixedToken(), knownAccounts: [ref]
        )
        let snapshot = try await provider.fetch(ref)
        #expect(snapshot.displayName == "sam@example.com")
        #expect(snapshot.failure != nil, "the read failed and the row should say so")
    }

    /// Nothing is known only of an account nobody has ever signed into, and the
    /// identifier is then all there is.
    @Test func theIdentifierIsTheLastResort() async throws {
        let ref = AccountRef(id: "claude/u-1", provider: .claude, handle: "u-1")
        let provider = ClaudeUsageProvider(
            http: FailingHTTP(), tokens: FixedToken(), knownAccounts: [ref]
        )
        let snapshot = try await provider.fetch(ref)
        #expect(snapshot.displayName == "claude/u-1")
    }
}

/// The path that was still showing the identifier: not a failed request, but a
/// token that could not be obtained at all — which returns before the profile is
/// ever asked for.
@Suite struct NamingAnAccountWithNoUsableToken {

    private struct NoToken: ClaudeTokenSource {
        func accessToken(for handle: String) async throws -> String {
            throw ProviderFailure(kind: .needsLogin, diagnostic: "no saved refresh token")
        }
    }

    private struct UnusedHTTP: HTTPClient {
        func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
            Issue.record("the network was reached without a token")
            return (Data(), 500)
        }
        func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
            (Data(), 500)
        }
    }

    @Test func theRowKeepsTheNameEvenWithNoToken() async throws {
        let ref = AccountRef(id: "claude/u-1", provider: .claude, handle: "u-1",
                             lastKnownName: "sam@example.com")
        let provider = ClaudeUsageProvider(
            http: UnusedHTTP(), tokens: NoToken(), knownAccounts: [ref]
        )
        let snapshot = try await provider.fetch(ref)
        #expect(snapshot.displayName == "sam@example.com")
        #expect(snapshot.failure?.kind == .needsLogin)
    }

    @Test func withNoNameEverKnownTheIdentifierStands() async throws {
        let ref = AccountRef(id: "claude/u-1", provider: .claude, handle: "u-1")
        let provider = ClaudeUsageProvider(
            http: UnusedHTTP(), tokens: NoToken(), knownAccounts: [ref]
        )
        let snapshot = try await provider.fetch(ref)
        #expect(snapshot.displayName == "claude/u-1")
    }
}
