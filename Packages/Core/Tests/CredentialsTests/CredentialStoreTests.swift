import Testing
import Foundation
import ProviderKit
import ClaudeProvider
@testable import Credentials

private actor MemoryKeychain: KeychainAccess {
    private var items: [String: Data] = [:]
    private(set) var writes: [String] = []

    init(_ seed: [String: Data] = [:]) { items = seed }

    /// Records whether the caller was willing to let a dialog appear. A poll
    /// must never be.
    var lastPromptRequest: Bool?

    func read(service: String, promptIfNeeded: Bool) throws -> Data? {
        lastPromptRequest = promptIfNeeded
        return items[service]
    }
    func write(_ data: Data, service: String) throws {
        items[service] = data
        writes.append(service)
    }
    func writeCount(for service: String) -> Int { writes.filter { $0 == service }.count }

    /// Plant a value "from outside", the way the CLI itself does.
    /// Unlike `write`, this does not count towards the app's own writes.
    func seed(_ data: Data, service: String) { items[service] = data }
}

private actor SpyRefresher: TokenRefreshing {
    private(set) var calls: [String] = []
    var result: RefreshedTokens? = RefreshedTokens(accessToken: "fresh", refreshToken: "rot")

    func refresh(refreshToken: String) async throws -> RefreshedTokens {
        calls.append(refreshToken)
        if rejects { throw RefreshRejected() }
        guard let result else {
            throw ProviderFailure(kind: .needsLogin, diagnostic: "account sign-in required")
        }
        return result
    }
    func setResult(_ value: RefreshedTokens?) { result = value }

    /// Makes the next refresh come back as finally rejected rather than merely
    /// failed.
    var rejects = false
    func setRejects(_ value: Bool) { rejects = value }
}

private func cliCredentials(token: String, refresh: String = "refresh-A") -> Data {
    let json: [String: Any] = ["claudeAiOauth": [
        "accessToken": token,
        "refreshToken": refresh,
        "expiresAt": 4_102_444_800_000,
        "subscriptionType": "max",
    ]]
    return try! JSONSerialization.data(withJSONObject: json)
}

/// The keychain read cache is off: these tests check what the store does,
/// not how long it holds on to what it read.
private func makeStore(
    _ keychain: MemoryKeychain, _ refresher: SpyRefresher = SpyRefresher()
) async -> CredentialStore {
    let store = CredentialStore(keychain: keychain, refresher: refresher, cacheWindow: 0)
    await store.load()
    return store
}

@Test func activeAccountReadsTokenStraightFromCLI() async throws {
    let keychain = MemoryKeychain([CredentialStore.cliService: cliCredentials(token: "live-tok")])
    let store = await makeStore(keychain)
    try await store.syncWithCLI(profileUUID: "u-1", displayName: "a@b.c")

    #expect(try await store.accessToken(for: "u-1") == "live-tok")
}

@Test func activeAccountIsNeverRefreshedNorWrittenBack() async throws {
    let keychain = MemoryKeychain([CredentialStore.cliService: cliCredentials(token: "live-tok")])
    let refresher = SpyRefresher()
    let store = await makeStore(keychain, refresher)
    try await store.syncWithCLI(profileUUID: "u-1", displayName: "a@b.c")
    _ = try await store.accessToken(for: "u-1")

    // Refreshing the active account would sign the CLI out — it must not happen.
    #expect(await refresher.calls.isEmpty)
    #expect(await keychain.writeCount(for: CredentialStore.cliService) == 0)
}

@Test func picksUpFreshTokenAfterCLIRefreshesItself() async throws {
    let keychain = MemoryKeychain([CredentialStore.cliService: cliCredentials(token: "old")])
    let store = await makeStore(keychain)
    try await store.syncWithCLI(profileUUID: "u-1", displayName: "a@b.c")
    #expect(try await store.accessToken(for: "u-1") == "old")

    await keychain.seed(cliCredentials(token: "new"), service: CredentialStore.cliService)
    #expect(try await store.accessToken(for: "u-1") == "new")
}

@Test func keepsRefreshTokenSoAccountSurvivesSwitching() async throws {
    let keychain = MemoryKeychain([
        CredentialStore.cliService: cliCredentials(token: "tok-A", refresh: "refresh-A")
    ])
    let refresher = SpyRefresher()
    let store = await makeStore(keychain, refresher)
    try await store.syncWithCLI(profileUUID: "u-1", displayName: "a@b.c")

    // The user ran /login into the second account: the keychain now holds another token.
    await keychain.seed(
        cliCredentials(token: "tok-B", refresh: "refresh-B"), service: CredentialStore.cliService
    )
    try await store.syncWithCLI(profileUUID: "u-2", displayName: "b@b.c")

    // The first account is now inactive — it is refreshed from the saved copy.
    #expect(try await store.accessToken(for: "u-1") == "fresh")
    #expect(await refresher.calls == ["refresh-A"])

    // The second is active now — read directly, with no refresh.
    #expect(try await store.accessToken(for: "u-2") == "tok-B")
    #expect(await refresher.calls == ["refresh-A"])
}

@Test func storesRotatedRefreshTokenForNextTime() async throws {
    let keychain = MemoryKeychain([
        CredentialStore.cliService: cliCredentials(token: "tok-A", refresh: "refresh-A")
    ])
    let refresher = SpyRefresher()
    let store = await makeStore(keychain, refresher)
    try await store.syncWithCLI(profileUUID: "u-1", displayName: "a@b.c")
    await keychain.seed(cliCredentials(token: "tok-B", refresh: "refresh-B"),
                        service: CredentialStore.cliService)
    try await store.syncWithCLI(profileUUID: "u-2", displayName: "b@b.c")

    _ = try await store.accessToken(for: "u-1")
    _ = try await store.accessToken(for: "u-1")

    // The second attempt goes out with the new token, not the burnt one.
    #expect(await refresher.calls == ["refresh-A", "rot"])
}

@Test func bothAccountsStayVisibleAfterSwitching() async throws {
    let keychain = MemoryKeychain([CredentialStore.cliService: cliCredentials(token: "t")])
    let store = await makeStore(keychain)
    try await store.syncWithCLI(profileUUID: "u-1", displayName: "a@b.c")
    try await store.syncWithCLI(profileUUID: "u-2", displayName: "b@b.c")

    #expect(await store.knownRefs().map(\.handle).sorted() == ["u-1", "u-2"])
}

@Test func syncingSameAccountTwiceDoesNotDuplicate() async throws {
    let keychain = MemoryKeychain([CredentialStore.cliService: cliCredentials(token: "t")])
    let store = await makeStore(keychain)
    try await store.syncWithCLI(profileUUID: "u-1", displayName: "a@b.c")
    try await store.syncWithCLI(profileUUID: "u-1", displayName: "a@b.c")

    #expect(await store.knownRefs().count == 1)
}

@Test func remembersAccountsAcrossRestart() async throws {
    let keychain = MemoryKeychain([CredentialStore.cliService: cliCredentials(token: "t")])
    let first = await makeStore(keychain)
    try await first.syncWithCLI(profileUUID: "u-1", displayName: "a@b.c")

    let second = await makeStore(keychain)
    #expect(await second.knownRefs().map(\.handle) == ["u-1"])
}

@Test func deadRefreshTokenMeansNeedsLogin() async throws {
    let keychain = MemoryKeychain([CredentialStore.cliService: cliCredentials(token: "tok-A")])
    let refresher = SpyRefresher()
    await refresher.setResult(nil)
    let store = await makeStore(keychain, refresher)
    try await store.syncWithCLI(profileUUID: "u-1", displayName: "a@b.c")
    await keychain.seed(cliCredentials(token: "tok-B", refresh: "refresh-B"),
                        service: CredentialStore.cliService)
    try await store.syncWithCLI(profileUUID: "u-2", displayName: "b@b.c")

    await #expect(throws: ProviderFailure.self) {
        _ = try await store.accessToken(for: "u-1")
    }
}

@Test func unknownAccountMeansNeedsLogin() async {
    let store = await makeStore(MemoryKeychain())
    await #expect(throws: ProviderFailure.self) {
        _ = try await store.accessToken(for: "unknown")
    }
}

// ===== account states and forgetting =====

@Test func statesDistinguishActiveFromRefreshed() async throws {
    let keychain = MemoryKeychain([
        CredentialStore.cliService: cliCredentials(token: "tok-A", refresh: "refresh-A")
    ])
    let store = await makeStore(keychain)
    try await store.syncWithCLI(profileUUID: "u-1", displayName: "a@b.c")
    await keychain.seed(cliCredentials(token: "tok-B", refresh: "refresh-B"),
                        service: CredentialStore.cliService)
    try await store.syncWithCLI(profileUUID: "u-2", displayName: "b@b.c")

    let states = await store.accountStates()
    let byHandle = Dictionary(uniqueKeysWithValues: states.map { ($0.account.handle, $0.state) })
    #expect(byHandle["u-2"] == .activeInCLI)
    #expect(byHandle["u-1"] == .refreshed)
}

@Test func accountWithoutCopyNeedsLogin() async throws {
    // The CLI keychain is empty — there was nowhere to copy a refresh token from.
    let store = await makeStore(MemoryKeychain())
    try await store.syncWithCLI(profileUUID: "u-9", displayName: "c@b.c")

    let states = await store.accountStates()
    #expect(states.first?.state == .needsLogin)
}

@Test func forgetRemovesAccountButNotTheCLIEntry() async throws {
    let keychain = MemoryKeychain([CredentialStore.cliService: cliCredentials(token: "t")])
    let store = await makeStore(keychain)
    try await store.syncWithCLI(profileUUID: "u-1", displayName: "a@b.c")
    try await store.forget(handle: "u-1")

    #expect(await store.knownRefs().isEmpty)
    // The CLI sign-in is untouched — that is what the "Forget" button promises.
    #expect(await keychain.writeCount(for: CredentialStore.cliService) == 0)
}

@Test func forgettingUnknownAccountIsHarmless() async throws {
    let store = await makeStore(MemoryKeychain())
    try await store.forget(handle: "no such handle")
    #expect(await store.knownRefs().isEmpty)
}

@Test func loggedInAccountIsStoredAsRefreshed() async throws {
    let store = await makeStore(MemoryKeychain())
    try await store.addLoggedInAccount(
        uuid: "u-web", displayName: "web@b.c", refreshToken: "rt-web"
    )
    let states = await store.accountStates()
    #expect(states.first?.state == .refreshed)
    #expect(states.first?.account.displayName == "web@b.c")
}

/// A keychain dialog raised by a five-minute timer is one nobody is looking for.
/// `SecItemCopyMatching` blocks until it is answered, and it was watched sitting
/// unanswered for eighty-four minutes with the app frozen behind it — so a poll
/// asks for no dialog and takes the error instead.
@Suite struct AskingForPermissionOnlyWhenSomebodyIsLooking {

    private func prepared() async -> (CredentialStore, MemoryKeychain) {
        let keychain = MemoryKeychain()
        await keychain.seed(cliCredentials(token: "t"), service: "Claude Code-credentials")
        return (await makeStore(keychain), keychain)
    }

    @Test func aPollDoesNotAskForADialog() async {
        let (store, keychain) = await prepared()
        try? await store.syncWithCLI(profileUUID: "u-1", displayName: "a@example.com")
        let asked = await keychain.lastPromptRequest
        #expect(asked == false,
                "a poll asked the keychain for permission to put a dialog on screen")
    }

    @Test func aRefreshTheUserAskedForMayShowTheDialog() async {
        let (store, keychain) = await prepared()
        await store.setPromptAllowed(true)
        try? await store.syncWithCLI(profileUUID: "u-1", displayName: "a@example.com")
        let asked = await keychain.lastPromptRequest
        #expect(asked == true, "an action the person took was still not allowed to ask")
    }

    /// Left up, the switch would let the next timer tick raise the dialog this
    /// whole change exists to prevent.
    @Test func theSwitchGoesBackDown() async {
        let (store, keychain) = await prepared()
        await store.setPromptAllowed(true)
        try? await store.syncWithCLI(profileUUID: "u-1", displayName: "a@example.com")
        await store.setPromptAllowed(false)

        try? await store.syncWithCLI(profileUUID: "u-1", displayName: "a@example.com")
        let asked = await keychain.lastPromptRequest
        #expect(asked == false)
        let stillAllowed = await store.isPromptAllowed
        #expect(!stillAllowed)
    }
}

/// A token the server has finished with is dropped rather than kept and re-sent
/// on every poll. The account stays in the list: removing it would hide the one
/// thing the reader needs to act on, and signing in gives it a working token
/// again.
@Suite struct DroppingATokenTheServerRejected {

    private func storeWithAnInactiveAccount() async -> (CredentialStore, MemoryKeychain, SpyRefresher) {
        let keychain = MemoryKeychain()
        let refresher = SpyRefresher()
        let store = await makeStore(keychain, refresher)

        // Signed in, then the CLI moves on: the account keeps its own copy.
        await keychain.seed(cliCredentials(token: "t"), service: "Claude Code-credentials")
        try? await store.syncWithCLI(profileUUID: "u-1", displayName: "sam@example.com")
        await keychain.seed(cliCredentials(token: "other", refresh: "refresh-B"),
                            service: "Claude Code-credentials")
        try? await store.syncWithCLI(profileUUID: "u-2", displayName: "alex@example.com")
        return (store, keychain, refresher)
    }

    @Test func theRejectedTokenIsNotAskedForTwice() async {
        let (store, _, refresher) = await storeWithAnInactiveAccount()
        await refresher.setRejects(true)

        _ = try? await store.accessToken(for: "u-1")
        let afterFirst = await refresher.calls.count
        #expect(afterFirst == 1, "the first attempt should reach the server")

        _ = try? await store.accessToken(for: "u-1")
        let afterSecond = await refresher.calls.count
        #expect(afterSecond == 1, """
            asked again with a token the server has finished with — \
            it was called \(afterSecond) times
            """)
    }

    @Test func theAccountStaysInTheList() async {
        let (store, _, refresher) = await storeWithAnInactiveAccount()
        await refresher.setRejects(true)
        _ = try? await store.accessToken(for: "u-1")

        let handles = await store.knownRefs().map(\.handle)
        #expect(handles.contains("u-1"), "the account vanished instead of asking to be signed into")
    }

    @Test func signingInAgainRevivesIt() async {
        let (store, keychain, refresher) = await storeWithAnInactiveAccount()
        await refresher.setRejects(true)
        _ = try? await store.accessToken(for: "u-1")

        // The person signs back in, and the CLI holds that account again.
        await keychain.seed(cliCredentials(token: "t", refresh: "refresh-C"),
                            service: "Claude Code-credentials")
        try? await store.syncWithCLI(profileUUID: "u-1", displayName: "sam@example.com")
        await refresher.setRejects(false)

        let token = try? await store.accessToken(for: "u-1")
        #expect(token != nil, "signing in again did not bring the account back")
    }
}


/// The CLI's keychain item is one item. A refusal to read it is refused for every
/// account at once — so it must not condemn accounts that hold a working copy of
/// their own, and must be the answer for the one that does not.
///
/// Written the other way round first: the refusal was rethrown wherever it
/// appeared, and three accounts that had been polling happily failed together the
/// moment the refusal started being detected properly.
@Suite struct ARefusalToReadTheCLIItem {

    private final class RefusingKeychain: KeychainAccess, @unchecked Sendable {
        private let lock = NSLock()
        private var own: Data?

        func read(service: String, promptIfNeeded: Bool) throws -> Data? {
            if service == "Claude Code-credentials" {
                throw ProviderFailure(kind: .needsPermission, diagnostic: "refused")
            }
            lock.lock(); defer { lock.unlock() }
            return own
        }
        func write(_ data: Data, service: String) throws {
            lock.lock(); own = data; lock.unlock()
        }
    }

    private func store(withCopyFor handle: String?) async -> CredentialStore {
        let keychain = RefusingKeychain()
        let store = CredentialStore(keychain: keychain, refresher: SpyRefresher(), cacheWindow: 0)
        if let handle {
            try? await store.addLoggedInAccount(
                uuid: handle, displayName: "sam@example.com", refreshToken: "copy"
            )
        }
        return store
    }

    @Test func anAccountWithItsOwnCopyStillWorks() async {
        let store = await store(withCopyFor: "u-1")
        let token = try? await store.accessToken(for: "u-1")
        #expect(token != nil, "a refusal about the CLI's item stopped an account that has its own")
    }

    /// An account with no copy of its own is one the app only ever saw through
    /// the CLI — which is exactly the item it is now refused.
    @Test func anAccountWithoutOneGetsTheRefusal() async {
        let keychain = RefusingKeychain()
        let store = CredentialStore(keychain: keychain, refresher: SpyRefresher(), cacheWindow: 0)
        try? await store.addLoggedInAccount(
            uuid: "u-1", displayName: "sam@example.com", refreshToken: "copy"
        )
        // The server finishes with the copy, so the account has none left.
        await (store as CredentialStore).forgetCopyForTesting(handle: "u-1")
        do {
            _ = try await store.accessToken(for: "u-1")
            Issue.record("no failure at all")
        } catch let failure as ProviderFailure {
            #expect(failure.kind == .needsPermission,
                    "reported \(failure.kind) — signing in again cannot help here")
        } catch {
            Issue.record("unexpected \(type(of: error))")
        }
    }
}

/// Changing the list and saving it are one act or neither.
///
/// They used to be two steps. When saving failed the list had already changed,
/// so the window showed one thing and the keychain held another: an account
/// forgotten until the next launch brought it back, or one added by a browser
/// sign-in that was gone by morning. Either way the app looked right and was not.
@Suite struct TheListAndTheKeychainAgree {

    private final class UnwritableKeychain: KeychainAccess, @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Data?
        var refuseWrites = false

        func read(service: String, promptIfNeeded: Bool) throws -> Data? {
            lock.lock(); defer { lock.unlock() }
            return service == "StatusChecker-accounts" ? stored : nil
        }
        func write(_ data: Data, service: String) throws {
            if refuseWrites {
                throw ProviderFailure(kind: .noData, diagnostic: "keychain is not writable")
            }
            lock.lock(); stored = data; lock.unlock()
        }
    }

    private func prepared() async -> (CredentialStore, UnwritableKeychain) {
        let keychain = UnwritableKeychain()
        let store = CredentialStore(keychain: keychain, refresher: SpyRefresher(), cacheWindow: 0)
        try? await store.addLoggedInAccount(
            uuid: "u-1", displayName: "sam@example.com", refreshToken: "copy"
        )
        return (store, keychain)
    }

    @Test func anAccountThatCannotBeSavedIsNotAdded() async {
        let (store, keychain) = await prepared()
        keychain.refuseWrites = true

        try? await store.addLoggedInAccount(
            uuid: "u-2", displayName: "alex@example.com", refreshToken: "copy2"
        )
        let handles = await store.knownRefs().map(\.handle)
        #expect(!handles.contains("u-2"), """
            the window would show an account the keychain never took — \
            gone by the next launch, with nothing to explain it
            """)
    }

    @Test func anAccountThatCannotBeForgottenStays() async {
        let (store, keychain) = await prepared()
        keychain.refuseWrites = true

        try? await store.forget(handle: "u-1")
        let handles = await store.knownRefs().map(\.handle)
        #expect(handles.contains("u-1"), """
            the row vanished while the keychain kept the account, \
            which comes back at the next launch
            """)
    }

    @Test func theFailureIsNotSwallowed() async {
        let (store, keychain) = await prepared()
        keychain.refuseWrites = true
        await #expect(throws: (any Error).self) {
            try await store.forget(handle: "u-1")
        }
    }

    @Test func aWritableKeychainStillWorks() async {
        let (store, _) = await prepared()
        try? await store.forget(handle: "u-1")
        let handles = await store.knownRefs().map(\.handle)
        #expect(handles.isEmpty)
    }
}

/// What happens when the stored list cannot be read.
///
/// The keychain item holds the only copy of the refresh token for every account
/// not currently active in the CLI. A refresh token is issued once; the copy is
/// taken while the account is active and cannot be fetched again. So a build
/// that cannot decode the item must not write to it — an edit would encode the
/// empty list `load` left behind and put it where the tokens were.
///
/// This is not hypothetical: `StoredAccount` decodes through the synthesised
/// `Codable`, which refuses a blob missing any non-optional field. Adding one
/// field would have put every install on this path.
@Suite struct AnUnreadableAccountList {

    @Test func loadingLeavesTheListEmptyAndSaysNothingIsThere() async {
        let keychain = MemoryKeychain([CredentialStore.ownService: Data("not json".utf8)])
        let store = CredentialStore(keychain: keychain, refresher: SpyRefresher(), cacheWindow: 0)
        await store.load()
        #expect(await store.knownRefs().isEmpty)
    }

    @Test func writingOverItIsRefused() async {
        let keychain = MemoryKeychain([CredentialStore.ownService: Data("not json".utf8)])
        let store = CredentialStore(keychain: keychain, refresher: SpyRefresher(), cacheWindow: 0)
        await store.load()

        await #expect(throws: WouldOverwriteUnreadableAccounts.self) {
            try await store.forget(handle: "anything")
        }
        #expect(await keychain.writeCount(for: CredentialStore.ownService) == 0,
                "the unreadable item was written to")
    }

    /// A readable item is written to as before — the refusal is about the one
    /// case, not about writing.
    @Test func aReadableListIsStillWritten() async throws {
        let list = try JSONEncoder().encode([
            StoredAccount(id: "claude/a", handle: "a", displayName: "A", refreshToken: "t")
        ])
        let keychain = MemoryKeychain([CredentialStore.ownService: list])
        let store = CredentialStore(keychain: keychain, refresher: SpyRefresher(), cacheWindow: 0)
        await store.load()
        #expect(await store.knownRefs().count == 1)

        try await store.forget(handle: "a")
        #expect(await store.knownRefs().isEmpty)
    }
}
