import Testing
import Foundation
import ProviderKit
import ClaudeProvider
@testable import Credentials

private actor MemoryKeychain: KeychainAccess {
    private var items: [String: Data] = [:]
    private(set) var writes: [String] = []

    init(_ seed: [String: Data] = [:]) { items = seed }

    func read(service: String) throws -> Data? {
        return items[service]
    }
    func write(_ data: Data, service: String) throws {
        items[service] = data
        writes.append(service)
    }
    func writeCount(for service: String) -> Int { writes.filter { $0 == service }.count }
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

private func makeStore(
    _ keychain: MemoryKeychain, _ refresher: SpyRefresher = SpyRefresher()
) async -> CredentialStore {
    let store = CredentialStore(keychain: keychain, refresher: refresher)
    await store.load()
    return store
}

@Test func unknownAccountMeansNeedsLogin() async {
    let store = await makeStore(MemoryKeychain())
    await #expect(throws: ProviderFailure.self) {
        _ = try await store.accessToken(for: "unknown")
    }
}

// ===== account states and forgetting =====

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

/// A read that fails is not an item that is empty.
///
/// `load` used to take both through one `try?`, so a keychain that refused the
/// read — locked, or an access check this build's signature no longer satisfies
/// — left the list empty with nothing to say it had been guessed at. The next
/// edit then encoded that empty list over the item, and a refresh token is
/// issued once: there is nowhere to fetch the lost ones from.
@Suite struct AnItemThatCouldNotBeRead {

    private final class RefusingKeychain: KeychainAccess, @unchecked Sendable {
        private let lock = NSLock()
        private var written: Data?

        func read(service: String) throws -> Data? {
            throw ProviderFailure(kind: .needsLogin, diagnostic: "keychain read failed, -25308")
        }
        func write(_ data: Data, service: String) throws {
            lock.lock(); written = data; lock.unlock()
        }
        var wasWritten: Bool { lock.lock(); defer { lock.unlock() }; return written != nil }
    }

    @Test func nothingIsWrittenOverIt() async {
        let keychain = RefusingKeychain()
        let store = CredentialStore(keychain: keychain, refresher: SpyRefresher())
        await store.load()

        await #expect(throws: WouldOverwriteUnreadableAccounts.self) {
            try await store.addLoggedInAccount(
                uuid: "u-1", displayName: "sam@example.com", refreshToken: "rt"
            )
        }
        #expect(!keychain.wasWritten, """
            the item that could not be read was written to — an empty list over \
            the only copy of every account's refresh token
            """)
    }

    /// And the account is not in the list either: the write is what makes an
    /// account real, and it did not happen.
    @Test func andTheAccountIsNotAdded() async {
        let store = CredentialStore(keychain: RefusingKeychain(), refresher: SpyRefresher())
        await store.load()
        try? await store.addLoggedInAccount(
            uuid: "u-1", displayName: "sam@example.com", refreshToken: "rt"
        )
        #expect(await store.knownRefs().isEmpty)
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

        func read(service: String) throws -> Data? {
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
        let store = CredentialStore(keychain: keychain, refresher: SpyRefresher())
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
        let store = CredentialStore(keychain: keychain, refresher: SpyRefresher())
        await store.load()
        #expect(await store.knownRefs().isEmpty)
    }

    @Test func writingOverItIsRefused() async {
        let keychain = MemoryKeychain([CredentialStore.ownService: Data("not json".utf8)])
        let store = CredentialStore(keychain: keychain, refresher: SpyRefresher())
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
        let store = CredentialStore(keychain: keychain, refresher: SpyRefresher())
        await store.load()
        #expect(await store.knownRefs().count == 1)

        try await store.forget(handle: "a")
        #expect(await store.knownRefs().isEmpty)
    }
}
