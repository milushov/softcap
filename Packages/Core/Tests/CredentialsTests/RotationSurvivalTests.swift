import Testing
import Foundation
import ProviderKit
import ClaudeProvider
@testable import Credentials

/// A clock the test moves by hand, as in `AccessTokenLifetimeTests`.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) { instant = start }
    var now: Date { lock.lock(); defer { lock.unlock() }; return instant }
    func advance(_ seconds: TimeInterval) {
        lock.lock(); instant += seconds; lock.unlock()
    }
}

/// A refresher whose first callers wait at a gate until the test opens it.
///
/// Concurrency bugs live in the moment a refresh is in flight; a mock that
/// answers instantly never has one in flight and cannot catch them. This one
/// suspends inside `refresh` so the test can arrange "a second caller arrives
/// while the first is still waiting" and then let both proceed.
private actor GatedRefresher: TokenRefreshing {
    private(set) var calls = 0
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func refresh(refreshToken: String) async throws -> RefreshedTokens {
        calls += 1
        let turn = calls
        if !open {
            await withCheckedContinuation { waiters.append($0) }
        }
        return RefreshedTokens(
            accessToken: "access-\(turn)", refreshToken: "rt-\(turn)", expiresIn: 3600
        )
    }

    func release() {
        open = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

/// Records what reaches the keychain and can be told to refuse writes.
private actor FlakyKeychain: KeychainAccess {
    private var items: [String: Data] = [:]
    private var failing = false

    func setFailing(_ on: Bool) { failing = on }
    func read(service: String) throws -> Data? { items[service] }
    func write(_ data: Data, service: String) throws {
        if failing {
            throw ProviderFailure(kind: .noData, diagnostic: "keychain refused the write")
        }
        items[service] = data
    }
}

private actor PlainKeychain: KeychainAccess {
    private var items: [String: Data] = [:]
    func read(service: String) throws -> Data? { items[service] }
    func write(_ data: Data, service: String) throws { items[service] = data }
}

/// Like `CountingRefresher`, but records which refresh token each call spent.
private actor SpendingRefresher: TokenRefreshing {
    private(set) var spent: [String] = []
    func refresh(refreshToken: String) async throws -> RefreshedTokens {
        spent.append(refreshToken)
        return RefreshedTokens(
            accessToken: "access-\(spent.count)", refreshToken: "rt-\(spent.count)",
            expiresIn: 3600
        )
    }
}

/// Waits for a condition that another task brings about, yielding in between.
/// Bounded, so a broken build fails the test instead of hanging it.
private func eventually(
    _ condition: @Sendable () async -> Bool
) async -> Bool {
    for _ in 0..<1000 {
        if await condition() { return true }
        await Task.yield()
    }
    return false
}

/// Two callers wanting a token while one refresh is already out must share its
/// answer, not send a second request with the same refresh token.
///
/// The store is an actor, but an actor is reentrant at every `await`: while one
/// caller waits on the network, another walks in. If the second one also
/// refreshes, the same single-use token is spent twice — the server rotates on
/// the first spend and answers the second with `invalid_grant`, which the store
/// rightly treats as "this account needs a sign-in". Two spends of one token is
/// self-inflicted account death.
@Suite struct OneRefreshServesEveryConcurrentCaller {

    @Test func aCallerArrivingMidRefreshSharesTheAnswer() async throws {
        let clock = TestClock()
        let gate = GatedRefresher()
        let store = CredentialStore(
            keychain: PlainKeychain(), refresher: gate, now: { clock.now }
        )
        try await store.addLoggedInAccount(
            uuid: "u-1", displayName: "sam@example.com", refreshToken: "rt"
        )

        let first = Task { try await store.accessToken(for: "u-1") }
        #expect(await eventually { await gate.calls == 1 }, "the first caller never reached the refresher")

        let second = Task { try await store.accessToken(for: "u-1") }
        // Let the second caller run as far as it can — to the shared refresh if
        // the store coalesces, or into a second spend of "rt" if it does not.
        for _ in 0..<100 { await Task.yield() }
        await gate.release()

        let served = try await (first.value, second.value)
        #expect(served.0 == served.1, "two callers were served different tokens for one account")
        let calls = await gate.calls
        #expect(calls == 1, """
            \(calls) refreshes for one account at one moment — the second spent \
            a refresh token the first had already rotated away
            """)
    }
}

/// The keychain refusing a write must not cost the rotation. The reply is the
/// only copy of the new refresh token; if it cannot be written now, it is kept
/// and written at the next opportunity — not dropped with `try?`.
@Suite struct ARefusedWriteDoesNotCostTheRotation {

    @Test func theRotationIsWrittenAtTheNextOpportunity() async throws {
        let clock = TestClock()
        let keychain = FlakyKeychain()
        let refresher = SpendingRefresher()
        let store = CredentialStore(
            keychain: keychain, refresher: refresher, now: { clock.now }
        )
        try await store.addLoggedInAccount(
            uuid: "u-1", displayName: "sam@example.com", refreshToken: "rt"
        )

        // The refresh succeeds; writing its rotation down does not.
        await keychain.setFailing(true)
        _ = try await store.accessToken(for: "u-1")

        // The keychain recovers, and the next request — served from the held
        // token, no refresh involved — is the opportunity to write.
        await keychain.setFailing(false)
        clock.advance(300)
        _ = try await store.accessToken(for: "u-1")

        // A relaunch after the held token expires proves what the keychain
        // holds: the rotation, or the token the server retired.
        clock.advance(4000)
        let relaunched = CredentialStore(
            keychain: keychain, refresher: refresher, now: { clock.now }
        )
        await relaunched.load()
        _ = try await relaunched.accessToken(for: "u-1")

        let last = await refresher.spent.last
        #expect(last == "rt-1", """
            the relaunch spent \(last ?? "nothing") — the rotation the refused \
            write was supposed to deliver never reached the keychain
            """)
    }
}

/// An account forgotten while its refresh is in flight is let go: the reply
/// belongs to nobody, and the caller is told to sign in rather than served a
/// token for an account that no longer exists.
///
/// The store used to keep the account's position across the network call and
/// write the reply back through it — an index into a list that a `forget` had
/// meanwhile emptied.
@Suite struct AnAccountForgottenMidRefreshIsLetGo {

    @Test func theReplyIsDroppedAndTheCallerToldToSignIn() async throws {
        let clock = TestClock()
        let gate = GatedRefresher()
        let store = CredentialStore(
            keychain: PlainKeychain(), refresher: gate, now: { clock.now }
        )
        try await store.addLoggedInAccount(
            uuid: "u-1", displayName: "sam@example.com", refreshToken: "rt"
        )

        let caller = Task { try await store.accessToken(for: "u-1") }
        #expect(await eventually { await gate.calls == 1 }, "the caller never reached the refresher")

        try await store.forget(handle: "u-1")
        await gate.release()

        switch await caller.result {
        case .success(let token):
            Issue.record("served \(token) for an account forgotten while the refresh was out")
        case .failure(let error):
            #expect((error as? ProviderFailure)?.kind == .needsLogin)
        }
        #expect(await store.knownRefs().isEmpty, "the forgotten account came back")
    }
}
