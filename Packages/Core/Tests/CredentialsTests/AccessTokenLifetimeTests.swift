import Testing
import Foundation
import ProviderKit
import ClaudeProvider
@testable import Credentials

/// A clock the test moves by hand. Real time would make these tests either slow
/// or flaky, and the thing under test is entirely about elapsed time.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) { instant = start }
    var now: Date { lock.lock(); defer { lock.unlock() }; return instant }
    func advance(_ seconds: TimeInterval) {
        lock.lock(); instant += seconds; lock.unlock()
    }
}

/// Counts refreshes and can be told how long the token it hands out is good for.
private actor CountingRefresher: TokenRefreshing {
    private(set) var calls = 0
    private var lifetime: TimeInterval?
    private var rotation: String?

    init(lifetime: TimeInterval? = 3600, rotation: String? = nil) {
        self.lifetime = lifetime
        self.rotation = rotation
    }

    func refresh(refreshToken: String) async throws -> RefreshedTokens {
        calls += 1
        return RefreshedTokens(
            accessToken: "access-\(calls)", refreshToken: rotation, expiresIn: lifetime
        )
    }
}

private actor PlainKeychain: KeychainAccess {
    private var items: [String: Data] = [:]
    func read(service: String, promptIfNeeded: Bool) throws -> Data? { items[service] }
    func write(_ data: Data, service: String) throws { items[service] = data }
}

/// An access token is held until it is nearly spent, instead of being fetched
/// again on every poll.
///
/// Every refresh burns the refresh token: Anthropic rotates it on each use, and
/// the replacement is only ours once it reaches the keychain. Refreshing on a
/// five-minute timer meant roughly 288 rotations a day per account, and 288
/// chances a day for a lost reply or a process killed at the wrong moment to
/// leave the app holding a token the server had already retired — which strands
/// the account until somebody signs in again.
///
/// The access token the server hands back is good for far longer than the poll
/// interval, and the reply says how long. That answer used to be discarded.
@Suite struct AnAccessTokenIsHeldUntilItIsNearlySpent {

    private func store(
        _ clock: TestClock, _ refresher: CountingRefresher
    ) async -> CredentialStore {
        let store = CredentialStore(
            keychain: PlainKeychain(), refresher: refresher,
            cacheWindow: 0, now: { clock.now }
        )
        try? await store.addLoggedInAccount(
            uuid: "u-1", displayName: "sam@example.com", refreshToken: "rt"
        )
        return store
    }

    @Test func theSameTokenServesEveryPollWithinItsLife() async throws {
        let clock = TestClock()
        let refresher = CountingRefresher(lifetime: 3600)
        let store = await store(clock, refresher)

        // Twelve polls at the default five-minute interval — one hour of running.
        for _ in 0..<12 {
            _ = try await store.accessToken(for: "u-1")
            clock.advance(300)
        }

        let calls = await refresher.calls
        #expect(calls == 1, """
            refreshed \(calls) times in an hour on a token good for an hour — \
            each one rotates the refresh token and risks stranding the account
            """)
    }

    @Test func aSpentTokenIsReplaced() async throws {
        let clock = TestClock()
        let refresher = CountingRefresher(lifetime: 3600)
        let store = await store(clock, refresher)

        #expect(try await store.accessToken(for: "u-1") == "access-1")
        clock.advance(3601)
        #expect(try await store.accessToken(for: "u-1") == "access-2")
    }

    /// Replaced a little early, so a token cannot expire between the check and
    /// the request it was fetched for.
    @Test func andReplacedShortlyBeforeItExpires() async throws {
        let clock = TestClock()
        let refresher = CountingRefresher(lifetime: 3600)
        let store = await store(clock, refresher)

        _ = try await store.accessToken(for: "u-1")
        clock.advance(3600 - 30)          // thirty seconds of life left
        _ = try await store.accessToken(for: "u-1")

        let calls = await refresher.calls
        #expect(calls == 2, "a token about to expire was used instead of replaced")
    }

    /// If the reply does not say how long the token lasts, nothing is assumed and
    /// the old behaviour stands. Guessing a lifetime would hand out a token the
    /// server had already retired, and the failure would look like a dead account.
    @Test func aReplyThatNamesNoLifetimeIsNotHeld() async throws {
        let clock = TestClock()
        let refresher = CountingRefresher(lifetime: nil)
        let store = await store(clock, refresher)

        _ = try await store.accessToken(for: "u-1")
        _ = try await store.accessToken(for: "u-1")

        #expect(await refresher.calls == 2)
    }

    /// Holding a token must not stop the rotated refresh token being written
    /// down: that is the credential the account survives on.
    @Test func theRotatedRefreshTokenIsStillKept() async throws {
        let clock = TestClock()
        let refresher = CountingRefresher(lifetime: 3600, rotation: "rt-2")
        let store = await store(clock, refresher)

        _ = try await store.accessToken(for: "u-1")
        let states = await store.accountStates()
        #expect(states.first?.account.refreshToken == "rt-2")
    }

    /// One account's token must not be handed to another.
    @Test func eachAccountHoldsItsOwn() async throws {
        let clock = TestClock()
        let refresher = CountingRefresher(lifetime: 3600)
        let store = await store(clock, refresher)
        try await store.addLoggedInAccount(
            uuid: "u-2", displayName: "alex@example.com", refreshToken: "rt-b"
        )

        let first = try await store.accessToken(for: "u-1")
        let second = try await store.accessToken(for: "u-2")
        #expect(first != second, "both accounts were served the same access token")
    }
}

/// The refresher has to read the lifetime out of the reply before anything can
/// hold the token for it.
@Suite struct TheRefreshReplySaysHowLongTheTokenLasts {

    private struct StubHTTP: HTTPClient {
        var response: (Data, Int)
        func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
            (Data(), 404)
        }
        func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
            response
        }
    }

    @Test func itIsReadFromExpiresIn() async throws {
        let http = StubHTTP(
            response: (Data(#"{"access_token":"at","expires_in":28800}"#.utf8), 200)
        )
        let tokens = try await AnthropicTokenRefresher(http: http).refresh(refreshToken: "old")
        #expect(tokens.expiresIn == 28800)
    }

    /// A reply without the field is not an error — it means nothing may be
    /// assumed about the lifetime.
    @Test func andIsAbsentWhenTheReplyOmitsIt() async throws {
        let http = StubHTTP(response: (Data(#"{"access_token":"at"}"#.utf8), 200))
        let tokens = try await AnthropicTokenRefresher(http: http).refresh(refreshToken: "old")
        #expect(tokens.expiresIn == nil)
    }
}

/// Forgetting an account lets go of its token too.
///
/// The held token lives in memory, which is why it is not in the keychain — but
/// "not written down" is not the same as "let go of". An account the reader has
/// removed should leave nothing behind that could still be sent on its behalf,
/// and signing back into it must fetch a token afresh rather than resurrect the
/// one held from before.
@Suite struct ForgettingAnAccountLetsGoOfItsToken {

    @Test func signingBackInDoesNotResurrectTheOldOne() async throws {
        let clock = TestClock()
        let refresher = CountingRefresher(lifetime: 3600)
        let store = CredentialStore(
            keychain: PlainKeychain(), refresher: refresher,
            cacheWindow: 0, now: { clock.now }
        )
        try await store.addLoggedInAccount(
            uuid: "u-1", displayName: "sam@example.com", refreshToken: "rt"
        )
        #expect(try await store.accessToken(for: "u-1") == "access-1")

        try await store.forget(handle: "u-1")
        try await store.addLoggedInAccount(
            uuid: "u-1", displayName: "sam@example.com", refreshToken: "rt-new"
        )

        let served = try await store.accessToken(for: "u-1")
        #expect(served == "access-2", """
            served \(served) — the token held for the forgotten account was \
            handed to the one that replaced it
            """)
    }
}
