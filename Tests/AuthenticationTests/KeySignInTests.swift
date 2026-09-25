import Testing
import Foundation
import ProviderKit
import Credentials

private actor KeyAccounts: KeychainAccess {
    private var data: Data?
    private let fails: Bool

    init(fails: Bool = false) { self.fails = fails }

    func read(service: String) throws -> Data? { data }
    func write(_ data: Data, service: String) async throws {
        if fails {
            throw ProviderFailure(kind: .needsLogin, diagnostic: "simulated persistence failure")
        }
        self.data = data
    }
}

private struct NeverRefreshes: TokenRefreshing {
    func refresh(refreshToken: String) async throws -> RefreshedTokens {
        Issue.record("a key sign-in must not refresh anything")
        throw CancellationError()
    }
}

/// A service that accepts one key and refuses every other.
private actor ScriptedKey: KeyAuthenticating {
    nonisolated let provider: ProviderID = .glm

    private let good: String
    private(set) var offered: [String] = []

    init(accepting good: String = "right-key") { self.good = good }

    func account(for key: String) async throws -> AuthenticatedAccount {
        offered.append(key)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == good else {
            throw ProviderFailure(kind: .needsLogin, diagnostic: "key refused")
        }
        return AuthenticatedAccount(
            account: AccountRef(
                id: "glm/abcdef0123456789", provider: .glm, handle: "abcdef0123456789",
                lastKnownName: "Pro"),
            tokens: RefreshedTokens(accessToken: trimmed, refreshToken: nil))
    }
}

/// A service that can be held mid-check, so the state between pressing Done
/// and the answer arriving can be looked at.
private actor GatedKey: KeyAuthenticating {
    nonisolated let provider: ProviderID = .glm
    private var waiting: CheckedContinuation<Void, Never>?
    private var arrived = false

    func account(for key: String) async throws -> AuthenticatedAccount {
        arrived = true
        await withCheckedContinuation { waiting = $0 }
        return AuthenticatedAccount(
            account: AccountRef(
                id: "glm/abcdef0123456789", provider: .glm, handle: "abcdef0123456789",
                lastKnownName: "Pro"),
            tokens: RefreshedTokens(accessToken: key, refreshToken: nil))
    }

    var reached: Bool { arrived }
    func release() { waiting?.resume(); waiting = nil }
}

@MainActor
private final class Browser {
    var opened: [URL] = []
    func open(_ url: URL) -> Bool { opened.append(url); return true }
}

@MainActor
private func eventually(_ condition: () async -> Bool) async -> Bool {
    let end = ContinuousClock.now.advanced(by: .seconds(3))
    while ContinuousClock.now < end {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}

/// The third shape of sign-in: nothing is granted, the credential is handed
/// over. Until somebody types, nothing at all is happening.
@Suite @MainActor struct KeySignIn {

    private func store(_ keychain: KeyAccounts = KeyAccounts()) -> CredentialStore {
        CredentialStore(
            keychain: keychain, refresher: NeverRefreshes(), codexRefresher: NeverRefreshes(),
            copilotRefresher: NeverRefreshes())
    }

    private func controller(
        _ service: ScriptedKey, store: CredentialStore? = nil, browser: Browser = Browser()
    ) -> LoginController {
        LoginController(
            store: store ?? self.store(),
            keyAuthentication: { _ in service },
            openURL: browser.open)
    }

    @Test func startingAsksForAKeyAndDoesNothingElse() async throws {
        let browser = Browser()
        let service = ScriptedKey()
        let model = controller(service, browser: browser)

        model.start(provider: .glm)

        #expect(model.keyExpected)
        #expect(model.isRunning)
        // No browser, no code, no request. The whole of this sign-in is the
        // field, and nothing is in flight until it is filled.
        #expect(browser.opened.isEmpty)
        #expect(model.deviceGrant == nil)
        #expect(!model.manualCodeExpected)
        #expect(await service.offered.isEmpty)
        model.cancel()
    }

    @Test func theRightKeyBecomesAnAccountNamedForItsPlan() async throws {
        let store = store()
        let model = controller(ScriptedKey(), store: store)

        var completions: [AccountRef] = []
        model.didAddAccount = { ref, origin in
            #expect(origin == .settings)
            completions.append(ref)
        }

        model.start(provider: .glm)
        await model.submitKey("right-key")

        #expect(completions.map(\.id) == ["glm/abcdef0123456789"])
        #expect(model.completedSignIns == 1)
        #expect(model.successNotice?.provider == .glm)
        #expect(model.message == nil)
        #expect(!model.isRunning)
        // The attempt is over, so the field comes off the screen with it.
        #expect(!model.keyExpected)
        #expect(await store.knownRefs().map(\.lastKnownName) == ["Pro"])

        // And the key is served back, which is the whole reason the store
        // learned what a credential given by hand is.
        #expect(try await store.accessToken(for: AccountRef(
            id: "glm/abcdef0123456789", provider: .glm, handle: "abcdef0123456789")) == "right-key")
        model.didAddAccount = nil
    }

    /// Mistyping a key is the ordinary way this goes wrong, and the correction
    /// must not be a fresh sign-in.
    @Test func awrongKeyLeavesTheFieldStanding() async throws {
        let store = store()
        let service = ScriptedKey()
        let model = controller(service, store: store)

        model.start(provider: .glm)
        await model.submitKey("wrong-key")

        #expect(model.message != nil)
        #expect(model.keyExpected, "the field must stay up so the key can be corrected")
        #expect(model.isRunning)
        #expect(model.completedSignIns == 0)
        #expect(await store.knownRefs().isEmpty)

        // And the same attempt takes the corrected key.
        await model.submitKey("right-key")
        #expect(model.completedSignIns == 1)
        #expect(await service.offered == ["wrong-key", "right-key"])
        #expect(await store.knownRefs().count == 1)
    }

    @Test func cancellingTakesTheFieldDownAndSavesNothing() async throws {
        let store = store()
        let model = controller(ScriptedKey(), store: store)

        model.start(provider: .glm)
        model.cancel()

        #expect(!model.keyExpected)
        #expect(!model.isRunning)

        // A key submitted after cancelling belongs to nobody.
        await model.submitKey("right-key")
        #expect(model.completedSignIns == 0)
        #expect(await store.knownRefs().isEmpty)
    }

    @Test func aSaveThatFailsIsReportedAndNothingIsClaimed() async throws {
        let model = controller(ScriptedKey(), store: store(KeyAccounts(fails: true)))

        model.start(provider: .glm)
        await model.submitKey("right-key")

        #expect(model.message != nil)
        #expect(model.completedSignIns == 0)
        #expect(model.successNotice == nil)
    }

    /// One attempt at a time, whichever shape it is.
    @Test func aSecondStartWhileOneIsRunningIsIgnored() async throws {
        let service = ScriptedKey()
        let model = controller(service)

        model.start(provider: .glm)
        model.start(provider: .claude)

        #expect(model.request?.provider == .glm)
        #expect(model.keyExpected)
        model.cancel()
    }

    /// While the key is in use the field comes down, and that is what lets the
    /// screen show something is happening: a field standing means the app is
    /// waiting on a person, and a spinner beside one would claim otherwise.
    @Test func theFieldComesDownWhileTheKeyIsBeingUsed() async throws {
        let service = GatedKey()
        let model = LoginController(
            store: store(), keyAuthentication: { _ in service }, openURL: { _ in true })

        model.start(provider: .glm)
        #expect(model.keyExpected)

        let submitting = Task { await model.submitKey("a-key") }
        #expect(await eventually { await service.reached })
        #expect(!model.keyExpected, "the field must be down while the key is in use")
        #expect(model.isRunning)

        await service.release()
        await submitting.value
        #expect(model.completedSignIns == 1)
        #expect(!model.keyExpected)
    }

    /// Two hand-kept lists, and one has to be inside the other — the same
    /// check the device shape carries, for the same reason: a provider named
    /// only in the shape list would have a menu item that does nothing.
    @Test func everyKeyProviderIsOneTheControllerWillStart() {
        #expect(LoginController.keyProviders.isSubset(of: Set(LoginController.providers)))
    }

    /// And no provider is two shapes at once, which would make `start` pick by
    /// the order the branches happen to be written in.
    @Test func noProviderClaimsTwoShapesOfSignIn() {
        #expect(LoginController.keyProviders.isDisjoint(with: LoginController.deviceProviders))
    }
}
