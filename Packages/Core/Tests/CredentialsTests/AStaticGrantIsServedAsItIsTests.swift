import Testing
import Foundation
import ProviderKit
@testable import Credentials

private actor MemoryKeychain: KeychainAccess {
    private var items: [String: Data] = [:]
    func read(service: String) throws -> Data? { items[service] }
    func write(_ data: Data, service: String) throws { items[service] = data }
}

private actor StubRefresher: TokenRefreshing {
    private(set) var calls: [String] = []
    func refresh(refreshToken: String) async throws -> RefreshedTokens {
        calls.append(refreshToken)
        return RefreshedTokens(accessToken: "rotated", refreshToken: "next")
    }
}

/// An account with no refresh token means two opposite things, and which one it
/// means is the service's to say.
///
/// For a rotating service it means the grant has been spent, and refusing it is
/// the guard that stops a dead account being retried on every poll until
/// somebody notices. For a service issuing a token that does not expire it is
/// the ordinary resting state of an account that works, and refusing it would
/// report "sign in again", forever, about a token that answers — with no
/// sign-in able to fix it, because the next one produces a credential of
/// exactly the same shape.
///
/// Both halves live in one file on purpose. The change is a narrowing of one
/// guard, and a later widening of it by accident is the thing worth catching;
/// a test holding only the new half would pass on a build that had dropped the
/// old one.
@Suite struct AStaticGrantIsServedAsItIs {

    private func store(_ refresher: StubRefresher = StubRefresher()) -> CredentialStore {
        CredentialStore(keychain: MemoryKeychain(), refresher: refresher)
    }

    private func device(
        id: String = "copilot/4711", token: String = "gh-token", expiresIn: TimeInterval? = nil,
        refreshToken: String? = nil
    ) -> AuthenticatedAccount {
        AuthenticatedAccount(
            account: AccountRef(
                id: id, provider: .copilot, handle: String(id.split(separator: "/").last!),
                lastKnownName: "sam"),
            tokens: RefreshedTokens(
                accessToken: token, refreshToken: refreshToken, expiresIn: expiresIn))
    }

    @Test func aDeviceGrantIsSavedWithoutARefreshToken() async throws {
        let store = store()
        await store.load()
        try await store.addLoggedInAccount(device())

        #expect(await store.knownRefs().map(\.id) == ["copilot/4711"])
        #expect(try await store.accessToken(for: AccountRef(
            id: "copilot/4711", provider: .copilot, handle: "4711")) == "gh-token")
    }

    /// The old half, unchanged.
    @Test func aRotatingServiceStillRefusesAGrantWithNothingToSpend() async throws {
        let store = store()
        await store.load()
        await #expect(throws: ProviderFailure.self) {
            try await store.addLoggedInAccount(AuthenticatedAccount(
                account: AccountRef(id: "claude/u", provider: .claude, handle: "u"),
                tokens: RefreshedTokens(accessToken: "only-this", refreshToken: nil)))
        }
        #expect(await store.knownRefs().isEmpty)
    }

    /// The shape the narrowing could widen into by accident: a rotating
    /// service's account holding a live access token and no refresh token.
    /// That is a grant the server has finished with, and it must still be
    /// refused however usable the token beside it looks.
    @Test func aSpentRotatingGrantStillAsksForASignIn() async throws {
        let keychain = MemoryKeychain()
        let refresher = StubRefresher()
        try await keychain.write(
            JSONEncoder().encode([
                StoredAccount(
                    id: "claude/u", handle: "u", displayName: "sam", refreshToken: nil,
                    tokenOrigin: .ownGrant, accessToken: "held",
                    accessGoodUntil: Date.distantFuture)
            ]),
            service: CredentialStore.ownService)

        let store = CredentialStore(keychain: keychain, refresher: refresher)
        await store.load()

        let ref = AccountRef(id: "claude/u", provider: .claude, handle: "u")
        await #expect(throws: ProviderFailure.self) { try await store.accessToken(for: ref) }
        #expect(await refresher.calls.isEmpty)
    }

    /// The same list, the same shape, the other service: served.
    @Test func theSameShapeAtAStaticServiceIsServed() async throws {
        let keychain = MemoryKeychain()
        try await keychain.write(
            JSONEncoder().encode([
                StoredAccount(
                    id: "copilot/4711", handle: "4711", displayName: "sam", refreshToken: nil,
                    tokenOrigin: .ownGrant, accessToken: "held", accessGoodUntil: nil)
            ]),
            service: CredentialStore.ownService)

        let store = CredentialStore(keychain: keychain, refresher: StubRefresher())
        await store.load()

        let ref = AccountRef(id: "copilot/4711", provider: .copilot, handle: "4711")
        #expect(try await store.accessToken(for: ref) == "held")
    }

    /// A key the person typed in is used, and recorded as what it is.
    ///
    /// Not a grant of ours — nothing was granted — and not a copy taken from a
    /// CLI, because nobody's files were read. What makes it usable is the
    /// reason the CLI rule exists: that rule is about rotation, and spending a
    /// refresh token copied from a CLI retires the CLI's own. A static key
    /// rotates nothing, so the person's editor goes on working unchanged.
    @Test func aKeyGivenByHandIsKeptAsGivenAndServed() async throws {
        let store = store()
        await store.load()
        try await store.addLoggedInAccount(AuthenticatedAccount(
            account: AccountRef(
                id: "glm/abcdef0123456789", provider: .glm, handle: "abcdef0123456789",
                lastKnownName: "Pro"),
            tokens: RefreshedTokens(accessToken: "plan-key", refreshToken: nil)))

        let ref = AccountRef(
            id: "glm/abcdef0123456789", provider: .glm, handle: "abcdef0123456789")
        #expect(try await store.accessToken(for: ref) == "plan-key")

        let recorded = await store.accountStates().first { $0.account.id == ref.id }?.account
        #expect(recorded?.tokenOrigin == .givenByHand)
        #expect(recorded?.isOwnGrant == false, "it is not a grant of ours and must not claim to be")
        #expect(recorded?.isSpendable == true)
    }

    /// A token copied from a CLI is refused at every service. The new path is
    /// reached only by a credential this app may use, and that rule has no
    /// exceptions to make for a service that does not rotate.
    @Test func aBorrowedTokenIsStillRefused() async throws {
        let keychain = MemoryKeychain()
        try await keychain.write(
            JSONEncoder().encode([
                StoredAccount(
                    id: "copilot/4711", handle: "4711", displayName: "sam", refreshToken: nil,
                    tokenOrigin: .copiedFromCLI, accessToken: "held", accessGoodUntil: nil)
            ]),
            service: CredentialStore.ownService)

        let store = CredentialStore(keychain: keychain, refresher: StubRefresher())
        await store.load()

        let ref = AccountRef(id: "copilot/4711", provider: .copilot, handle: "4711")
        await #expect(throws: ProviderFailure.self) { try await store.accessToken(for: ref) }
    }

    /// A static grant never reaches the refresher, however many polls ask.
    @Test func nothingIsEverRotatedForIt() async throws {
        let refresher = StubRefresher()
        let store = store(refresher)
        await store.load()
        try await store.addLoggedInAccount(device())

        let ref = AccountRef(id: "copilot/4711", provider: .copilot, handle: "4711")
        for _ in 0..<3 { _ = try await store.accessToken(for: ref) }
        #expect(await refresher.calls.isEmpty)
    }

    /// One refused request must not destroy the only credential there is.
    @Test func aRefusedRequestDoesNotDiscardTheGrant() async throws {
        let store = store()
        await store.load()
        try await store.addLoggedInAccount(device())

        let ref = AccountRef(id: "copilot/4711", provider: .copilot, handle: "4711")
        await store.invalidateAccessToken(for: ref, rejectedToken: "gh-token")
        #expect(try await store.accessToken(for: ref) == "gh-token")
    }

    /// When the service does state a deadline, it is kept and honoured: the
    /// flag decides what an absent refresh token means, not whether an expiry
    /// is believed.
    @Test func aStatedDeadlineIsStillObeyed() async throws {
        let clock = Clock()
        let store = CredentialStore(
            keychain: MemoryKeychain(), refresher: StubRefresher(),
            now: { clock.reading })
        await store.load()
        try await store.addLoggedInAccount(device(expiresIn: 3600))

        let ref = AccountRef(id: "copilot/4711", provider: .copilot, handle: "4711")
        #expect(try await store.accessToken(for: ref) == "gh-token")

        clock.advance(by: 7200)
        await #expect(throws: ProviderFailure.self) { try await store.accessToken(for: ref) }
    }

    /// And when it issues a refresh token after all, the ordinary path runs.
    @Test func aGrantThatDoesRotateIsRotated() async throws {
        let clock = Clock()
        let refresher = StubRefresher()
        let store = CredentialStore(
            keychain: MemoryKeychain(), refresher: StubRefresher(),
            copilotRefresher: refresher, now: { clock.reading })
        await store.load()
        try await store.addLoggedInAccount(device(expiresIn: 3600, refreshToken: "rt"))

        let ref = AccountRef(id: "copilot/4711", provider: .copilot, handle: "4711")
        #expect(try await store.accessToken(for: ref) == "gh-token")
        clock.advance(by: 7200)
        #expect(try await store.accessToken(for: ref) == "rotated")
        #expect(await refresher.calls == ["rt"])
    }
}

/// A clock a test can move.
private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_800_000_000)

    var reading: Date {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func advance(by seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        value = value.addingTimeInterval(seconds)
    }
}
