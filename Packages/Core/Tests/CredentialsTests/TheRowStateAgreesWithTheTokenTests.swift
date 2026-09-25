import Testing
import Foundation
import ProviderKit
@testable import Credentials

private actor MemoryKeychain: KeychainAccess {
    private var items: [String: Data] = [:]
    func read(service: String) throws -> Data? { items[service] }
    func write(_ data: Data, service: String) throws { items[service] = data }
}

private struct RefusingRefresher: TokenRefreshing {
    func refresh(refreshToken: String) async throws -> RefreshedTokens {
        // The rotating cases here hold a live access token, so no test in this
        // file should ever need the network. One that does is asking a
        // different question than the one this file holds.
        throw RefreshRejected()
    }
}

/// What a row says about an account and what the store will actually give it
/// must be the same answer.
///
/// They were not. `accountStates` asked `isOwnGrant && refreshToken != nil`,
/// which is only ever true of a service that rotates. A device grant and a key
/// given by hand both hold no refresh token — there is nothing to rotate — so
/// every such account was reported as needing a sign-in while the poller read
/// its limits perfectly well: a red badge and a `Sign in…` button on an account
/// that worked.
///
/// Two places answering one question is how that happened, and the two are
/// still two — one has a `String` to return and the other an enum. So they are
/// held together here instead: for every shape an account can be stored in, the
/// row says `refreshed` exactly when the token comes out.
@Suite struct TheRowStateAgreesWithTheToken {

    private struct Shape {
        let name: String
        let account: StoredAccount
    }

    private static func shapes() -> [Shape] {
        [
            Shape(name: "a rotating service holding a live grant", account: StoredAccount(
                id: "claude/u", handle: "u", displayName: "sam", refreshToken: "rt",
                tokenOrigin: .ownGrant, accessToken: "held",
                accessGoodUntil: .distantFuture)),
            Shape(name: "a rotating service whose grant is spent", account: StoredAccount(
                id: "claude/spent", handle: "spent", displayName: "sam", refreshToken: nil,
                tokenOrigin: .ownGrant, accessToken: "held", accessGoodUntil: .distantFuture)),
            Shape(name: "a device grant, which never rotates", account: StoredAccount(
                id: "copilot/1", handle: "1", displayName: "sam", refreshToken: nil,
                tokenOrigin: .ownGrant, accessToken: "gh-token", accessGoodUntil: nil)),
            Shape(name: "a device grant with nothing in it", account: StoredAccount(
                id: "copilot/2", handle: "2", displayName: "sam", refreshToken: nil,
                tokenOrigin: .ownGrant, accessToken: nil, accessGoodUntil: nil)),
            Shape(name: "a key given by hand", account: StoredAccount(
                id: "glm/abc", handle: "abc", displayName: "Pro", refreshToken: nil,
                tokenOrigin: .givenByHand, accessToken: "plan-key", accessGoodUntil: nil)),
            Shape(name: "a key given by hand and since emptied", account: StoredAccount(
                id: "glm/def", handle: "def", displayName: "Pro", refreshToken: nil,
                tokenOrigin: .givenByHand, accessToken: "", accessGoodUntil: nil)),
            // The shapes the first version of this suite did not vary, and the
            // divergence it therefore let through: `accessToken(for:)` checks
            // the stated deadline and `accountStates` did not, so an expired
            // static credential showed a green badge and no way back in.
            Shape(name: "a static credential still inside its stated life",
                  account: StoredAccount(
                    id: "copilot/dated", handle: "dated", displayName: "sam", refreshToken: nil,
                    tokenOrigin: .ownGrant, accessToken: "gh-token",
                    accessGoodUntil: .distantFuture)),
            Shape(name: "a static credential past its stated life", account: StoredAccount(
                id: "copilot/expired", handle: "expired", displayName: "sam", refreshToken: nil,
                tokenOrigin: .ownGrant, accessToken: "gh-token",
                accessGoodUntil: .distantPast)),
            Shape(name: "a key given by hand and past its stated life",
                  account: StoredAccount(
                    id: "kimi/expired", handle: "coding-abc", displayName: "Kimi Code",
                    refreshToken: nil, tokenOrigin: .givenByHand, accessToken: "sk-kimi",
                    accessGoodUntil: .distantPast)),
            Shape(name: "a token copied from a CLI", account: StoredAccount(
                id: "claude/cli", handle: "cli", displayName: "sam", refreshToken: "rt",
                tokenOrigin: .copiedFromCLI, accessToken: "held",
                accessGoodUntil: .distantFuture)),
            Shape(name: "a list written before the field existed", account: StoredAccount(
                id: "claude/old", handle: "old", displayName: "sam", refreshToken: "rt",
                tokenOrigin: nil, accessToken: "held", accessGoodUntil: .distantFuture)),
        ]
    }

    @Test func everyShapeSaysTheSameThingTwice() async throws {
        let keychain = MemoryKeychain()
        let shapes = Self.shapes()
        try await keychain.write(
            JSONEncoder().encode(shapes.map(\.account)), service: CredentialStore.ownService)

        let store = CredentialStore(keychain: keychain, refresher: RefusingRefresher())
        await store.load()

        let states = await store.accountStates()
        #expect(states.count == shapes.count, "the list did not come back whole")

        for shape in shapes {
            let stored = shape.account
            let said = states.first { $0.account.id == stored.id }?.state
            let ref = AccountRef(
                id: stored.id, provider: stored.provider, handle: stored.handle)

            var served = false
            do {
                _ = try await store.accessToken(for: ref)
                served = true
            } catch {
                served = false
            }

            #expect(said == (served ? .refreshed : .needsLogin), """
                \(shape.name): the row says \(said.map(String.init(describing:)) ?? "nothing") \
                and the store \(served ? "hands the token over" : "refuses it")
                """)
        }
    }

    /// An origin this build has not met costs one row and not the item.
    ///
    /// The synthesised decoder threw on an unknown value, and `load` reads a
    /// blob it cannot decode as present-but-unreadable — which refuses every
    /// write afterwards. One word nobody recognises would have taken every
    /// account with it and offered only starting over.
    @Test func anUnknownOriginCostsOnlyItsOwnRow() async throws {
        let keychain = MemoryKeychain()
        let blob = """
            [{"id":"claude/u","handle":"u","displayName":"sam","refreshToken":"rt",
              "tokenOrigin":"ownGrant","accessToken":"held"},
             {"id":"glm/future","handle":"future","displayName":"Pro","refreshToken":null,
              "tokenOrigin":"somethingLater","accessToken":"plan-key"}]
            """
        try await keychain.write(Data(blob.utf8), service: CredentialStore.ownService)

        let store = CredentialStore(keychain: keychain, refresher: RefusingRefresher())
        await store.load()

        #expect(await store.whyUnreadable() == nil, "the item must still be readable")
        #expect(await store.knownRefs().map(\.id).sorted() == ["claude/u", "glm/future"])

        let states = await store.accountStates()
        #expect(states.first { $0.account.id == "claude/u" }?.state == .refreshed)
        // Unknown means refused, which is the most cautious answer this type
        // has and is recovered by signing that one account in again.
        #expect(states.first { $0.account.id == "glm/future" }?.state == .needsLogin)
        #expect(states.first { $0.account.id == "glm/future" }?.account.tokenOrigin == nil)
    }

    /// And the check is not vacuous in either direction: some shapes work and
    /// some do not, so a version of this that always agreed would fail here.
    @Test func bothAnswersAreRepresented() async throws {
        let keychain = MemoryKeychain()
        try await keychain.write(
            JSONEncoder().encode(Self.shapes().map(\.account)),
            service: CredentialStore.ownService)
        let store = CredentialStore(keychain: keychain, refresher: RefusingRefresher())
        await store.load()

        let states = await store.accountStates().map(\.state)
        #expect(states.contains(.refreshed))
        #expect(states.contains(.needsLogin))
    }
}
