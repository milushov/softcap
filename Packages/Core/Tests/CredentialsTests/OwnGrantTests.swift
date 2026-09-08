import Testing
import Foundation
import ProviderKit
import ClaudeProvider
@testable import Credentials

/// A keychain that remembers which items were asked for.
///
/// The question these tests ask is not "what came back" but "what was touched".
/// Reading the CLI's item is the act that costs something: macOS checks it
/// against the item's access list every time, and the item belongs to Claude
/// Code, which rewrites it whenever it refreshes — taking any grant with it.
private actor WatchfulKeychain: KeychainAccess {
    private var items: [String: Data] = [:]
    private(set) var servicesRead: [String] = []

    init(_ seed: [String: Data] = [:]) { items = seed }

    func read(service: String, promptIfNeeded: Bool) throws -> Data? {
        servicesRead.append(service)
        return items[service]
    }
    func write(_ data: Data, service: String) throws { items[service] = data }

    func seed(_ data: Data, service: String) { items[service] = data }
    func readCount(for service: String) -> Int { servicesRead.filter { $0 == service }.count }
}

private actor StubRefresher: TokenRefreshing {
    private(set) var calls: [String] = []
    func refresh(refreshToken: String) async throws -> RefreshedTokens {
        calls.append(refreshToken)
        return RefreshedTokens(accessToken: "fresh-for-\(refreshToken)", refreshToken: nil)
    }
}

private func cliCredentials(token: String, refresh: String) -> Data {
    let json: [String: Any] = ["claudeAiOauth": [
        "accessToken": token,
        "refreshToken": refresh,
        "expiresAt": 4_102_444_800_000,
        "subscriptionType": "max",
    ]]
    return try! JSONSerialization.data(withJSONObject: json)
}

/// An account that holds a credential this app was granted in its own right
/// never reads the keychain item belonging to Claude Code.
///
/// This is the whole point of the change. Reading a foreign item is what raises
/// "Softcap wants to use your confidential information" — and no answer to that
/// dialog lasts, because the item's owner rewrites it on every token refresh and
/// the access list goes with it. An account with its own grant has no reason to
/// look there, and now does not.
@Suite struct AnAccountWithItsOwnGrantNeverReadsTheCLIItem {

    @Test func aBrowserSignInLeavesTheCLIItemAlone() async throws {
        let keychain = WatchfulKeychain([
            CredentialStore.cliService: cliCredentials(token: "cli-tok", refresh: "cli-refresh")
        ])
        let store = CredentialStore(
            keychain: keychain, refresher: StubRefresher(), cacheWindow: 0
        )
        await store.load()
        try await store.addLoggedInAccount(
            uuid: "u-web", displayName: "sam@example.com", refreshToken: "rt-web"
        )

        _ = try await store.accessToken(for: "u-web")

        let touched = await keychain.readCount(for: CredentialStore.cliService)
        #expect(touched == 0, """
            reading a token for an account with its own grant went to the CLI's \
            keychain item \(touched) time(s) — that read is the prompt
            """)
    }

    /// Ten polls, still nothing. A single read would be a bug; a read per poll is
    /// the bug that was actually shipped.
    @Test func repeatedPollsStillLeaveItAlone() async throws {
        let keychain = WatchfulKeychain([
            CredentialStore.cliService: cliCredentials(token: "cli-tok", refresh: "cli-refresh")
        ])
        let store = CredentialStore(
            keychain: keychain, refresher: StubRefresher(), cacheWindow: 0
        )
        await store.load()
        try await store.addLoggedInAccount(
            uuid: "u-web", displayName: "sam@example.com", refreshToken: "rt-web"
        )

        for _ in 0..<10 { _ = try await store.accessToken(for: "u-web") }

        #expect(await keychain.readCount(for: CredentialStore.cliService) == 0)
    }

    /// The account signed into with `claude /login` is still read from the CLI,
    /// and still never refreshed — rotating its token would sign the CLI out.
    /// That rule is older than this change and survives it.
    @Test func anAccountCopiedFromTheCLIStillReadsItDirectly() async throws {
        let keychain = WatchfulKeychain([
            CredentialStore.cliService: cliCredentials(token: "cli-tok", refresh: "cli-refresh")
        ])
        let refresher = StubRefresher()
        let store = CredentialStore(keychain: keychain, refresher: refresher, cacheWindow: 0)
        await store.load()
        try await store.syncWithCLI(profileUUID: "u-cli", displayName: "cli@example.com")

        #expect(try await store.accessToken(for: "u-cli") == "cli-tok")
        #expect(await refresher.calls.isEmpty, "the active CLI account was refreshed")
    }
}

/// What an account with no credential at all should tell the reader.
///
/// It used to say "Allow keychain access", because the only way it could ever
/// have been read was through the CLI's item, and that item was refused. With a
/// browser sign-in available per account, that is no longer true: signing in
/// gives the account a grant of its own and ends the matter permanently, while
/// granting keychain access ends it only until Claude Code next refreshes.
@Suite struct AnAccountWithNoCredentialAsksToBeSignedInto {

    private final class RefusingKeychain: KeychainAccess, @unchecked Sendable {
        private let lock = NSLock()
        private var own: Data?

        func read(service: String, promptIfNeeded: Bool) throws -> Data? {
            if service == CredentialStore.cliService {
                throw ProviderFailure(kind: .needsPermission, diagnostic: "refused")
            }
            lock.lock(); defer { lock.unlock() }
            return own
        }
        func write(_ data: Data, service: String) throws {
            lock.lock(); own = data; lock.unlock()
        }
    }

    @Test func itSaysSignIn() async throws {
        let refresher = RejectingRefresher()
        await refresher.setRejects(true)
        let store = CredentialStore(
            keychain: RefusingKeychain(), refresher: refresher, cacheWindow: 0
        )
        try await store.addLoggedInAccount(
            uuid: "u-1", displayName: "sam@example.com", refreshToken: "copy"
        )
        // The server finishes with the credential: this attempt drops it, which
        // is how an account comes to have nothing of its own.
        _ = try? await store.accessToken(for: "u-1")

        do {
            _ = try await store.accessToken(for: "u-1")
            Issue.record("no failure at all")
        } catch let failure as ProviderFailure {
            #expect(failure.kind == .needsLogin, """
                reported \(failure.kind) — the row would ask for keychain access, \
                which cannot hold, instead of the sign-in that can
                """)
        }
    }
}

/// A list written by a build that predates `tokenOrigin` must still decode.
///
/// `StoredAccount` decodes through the synthesised `Codable`, which refuses a
/// blob missing any non-optional field. The item holds the only copy of every
/// inactive account's refresh token, and `load` treats an undecodable item as
/// "present but unreadable" — which then refuses every write to protect it. A
/// required new field would put every existing install in that state at once:
/// no accounts in the window, and no way to add any.
@Suite struct AListWrittenBeforeOriginsWereRecorded {

    @Test func stillDecodes() async throws {
        // Exactly the shape the shipped build writes: no `tokenOrigin` key.
        let legacy = Data("""
        [{"id":"claude/u-1","handle":"u-1","displayName":"sam@example.com",\
        "refreshToken":"rt-old"}]
        """.utf8)
        let keychain = WatchfulKeychain([CredentialStore.ownService: legacy])
        let store = CredentialStore(
            keychain: keychain, refresher: StubRefresher(), cacheWindow: 0
        )
        await store.load()

        let handles = await store.knownRefs().map(\.handle)
        #expect(handles == ["u-1"], """
            the stored list stopped decoding — every install loses its accounts \
            and cannot write new ones
            """)
    }

    /// And the list stays writable, which is the half that turns a bad read into
    /// a lost account list.
    @Test func andStaysWritable() async throws {
        let legacy = Data("""
        [{"id":"claude/u-1","handle":"u-1","displayName":"sam@example.com",\
        "refreshToken":"rt-old"}]
        """.utf8)
        let keychain = WatchfulKeychain([CredentialStore.ownService: legacy])
        let store = CredentialStore(
            keychain: keychain, refresher: StubRefresher(), cacheWindow: 0
        )
        await store.load()

        try await store.addLoggedInAccount(
            uuid: "u-2", displayName: "alex@example.com", refreshToken: "rt-new"
        )
        #expect(await store.knownRefs().count == 2)
    }

    /// An account restored from such a list has no recorded origin, and the only
    /// origin it can have had is the CLI — the browser path is what introduced
    /// the field. It must not be mistaken for an own grant, or the app would
    /// refresh the active account's token and sign Claude Code out.
    @Test func itsTokenIsTreatedAsACLICopy() async throws {
        let legacy = Data("""
        [{"id":"claude/u-1","handle":"u-1","displayName":"sam@example.com",\
        "refreshToken":"cli-refresh"}]
        """.utf8)
        let keychain = WatchfulKeychain([
            CredentialStore.ownService: legacy,
            CredentialStore.cliService: cliCredentials(token: "cli-tok", refresh: "cli-refresh"),
        ])
        let refresher = StubRefresher()
        let store = CredentialStore(keychain: keychain, refresher: refresher, cacheWindow: 0)
        await store.load()

        #expect(try await store.accessToken(for: "u-1") == "cli-tok")
        #expect(await refresher.calls.isEmpty, """
            the active account was refreshed from a copy of the CLI's own token — \
            that rotates it server side and signs Claude Code out
            """)
    }
}

/// Signing into an account in the CLI must not take away the grant it already
/// had of its own.
///
/// `syncWithCLI` copies the CLI's refresh token onto every account it recognises,
/// which is right for accounts that have nothing else — the copy is what keeps
/// them visible after `/login` moves on. Applied to an account that signed in
/// through the browser it is actively harmful: the account would be left holding
/// the CLI's own token while still marked as an independent grant, and the next
/// poll would refresh it, rotate it server side, and sign Claude Code out. The
/// app for watching limits would have broken the tool it watches — the very
/// thing the read-only rule was written to prevent.
@Suite struct ACLISignInDoesNotDemoteAnOwnGrant {

    @Test func theOwnTokenSurvives() async throws {
        let keychain = WatchfulKeychain([
            CredentialStore.cliService: cliCredentials(token: "cli-tok", refresh: "cli-refresh")
        ])
        let refresher = StubRefresher()
        let store = CredentialStore(keychain: keychain, refresher: refresher, cacheWindow: 0)
        await store.load()
        try await store.addLoggedInAccount(
            uuid: "u-1", displayName: "sam@example.com", refreshToken: "rt-web"
        )

        // The same person then runs `claude /login` into that same account.
        try await store.syncWithCLI(profileUUID: "u-1", displayName: "sam@example.com")
        _ = try await store.accessToken(for: "u-1")

        let sent = await refresher.calls
        #expect(sent == ["rt-web"], """
            refreshed \(sent) — sending the CLI's own token to be rotated is \
            what signs Claude Code out
            """)
    }

    /// And the account still asks the CLI's item for nothing.
    @Test func andItStillNeverReadsTheCLIItem() async throws {
        let keychain = WatchfulKeychain([
            CredentialStore.cliService: cliCredentials(token: "cli-tok", refresh: "cli-refresh")
        ])
        let store = CredentialStore(
            keychain: keychain, refresher: StubRefresher(), cacheWindow: 0
        )
        await store.load()
        try await store.addLoggedInAccount(
            uuid: "u-1", displayName: "sam@example.com", refreshToken: "rt-web"
        )
        try await store.syncWithCLI(profileUUID: "u-1", displayName: "sam@example.com")

        let before = await keychain.readCount(for: CredentialStore.cliService)
        _ = try await store.accessToken(for: "u-1")
        let after = await keychain.readCount(for: CredentialStore.cliService)

        #expect(after == before, "vending a token opened the CLI's item again")
    }

    /// The name is still worth taking: it is the one thing the CLI knows that
    /// the stored account may not, and copying it cannot cost anything.
    @Test func butTheNameIsStillUpdated() async throws {
        let keychain = WatchfulKeychain([
            CredentialStore.cliService: cliCredentials(token: "cli-tok", refresh: "cli-refresh")
        ])
        let store = CredentialStore(
            keychain: keychain, refresher: StubRefresher(), cacheWindow: 0
        )
        await store.load()
        try await store.addLoggedInAccount(
            uuid: "u-1", displayName: "old@example.com", refreshToken: "rt-web"
        )
        try await store.syncWithCLI(profileUUID: "u-1", displayName: "new@example.com")

        #expect(await store.knownRefs().first?.lastKnownName == "new@example.com")
    }
}

/// Whether the five-minute poll has any reason to open the CLI's keychain item.
///
/// Reading it is the act that raises the dialog, and the dialog is only tolerable
/// once — at install, to pick up the account Claude Code is already signed into.
/// After that every read is a chance for the prompt to come back, because the
/// grant does not survive Claude Code rewriting the item.
///
/// So the poll asks first. With nothing stored there is an account to discover
/// and the read is worth it. With every account holding a grant of its own there
/// is nothing there the app does not already have, and it never looks again.
@Suite struct WhetherThePollHasAnyReasonToOpenTheCLIItem {

    private func store(_ keychain: WatchfulKeychain = WatchfulKeychain()) async -> CredentialStore {
        let store = CredentialStore(
            keychain: keychain, refresher: StubRefresher(), cacheWindow: 0
        )
        await store.load()
        return store
    }

    /// A fresh install: the account signed into with `claude /login` is exactly
    /// what the reader expects to see without doing anything, and one prompt at
    /// setup is the price they agreed to.
    @Test func withNothingStoredThereIsAnAccountToDiscover() async {
        #expect(await store().dependsOnCLI())
    }

    @Test func anAccountCopiedFromTheCLIStillNeedsIt() async throws {
        let keychain = WatchfulKeychain([
            CredentialStore.cliService: cliCredentials(token: "cli-tok", refresh: "cli-refresh")
        ])
        let store = await store(keychain)
        try await store.syncWithCLI(profileUUID: "u-1", displayName: "sam@example.com")

        #expect(await store.dependsOnCLI())
    }

    /// The state this whole change exists to reach.
    @Test func onceEveryAccountHasItsOwnGrantItIsNeverOpenedAgain() async throws {
        let store = await store()
        try await store.addLoggedInAccount(
            uuid: "u-1", displayName: "sam@example.com", refreshToken: "rt-1"
        )
        try await store.addLoggedInAccount(
            uuid: "u-2", displayName: "alex@example.com", refreshToken: "rt-2"
        )

        #expect(await store.dependsOnCLI() == false, """
            every account carries its own credential and the app would still \
            open Claude Code's item on every poll — which is the prompt coming back
            """)
    }

    /// One straggler is enough to keep looking: it has nowhere else to get a
    /// token from.
    @Test func oneAccountWithoutAGrantIsEnough() async throws {
        let keychain = WatchfulKeychain([
            CredentialStore.cliService: cliCredentials(token: "cli-tok", refresh: "cli-refresh")
        ])
        let store = await store(keychain)
        try await store.addLoggedInAccount(
            uuid: "u-1", displayName: "sam@example.com", refreshToken: "rt-1"
        )
        try await store.syncWithCLI(profileUUID: "u-2", displayName: "alex@example.com")

        #expect(await store.dependsOnCLI())
    }

    /// A list from before origins were recorded is all CLI copies as far as
    /// anyone knows, so it keeps its claim on the item.
    @Test func aListFromBeforeOriginsWereRecordedStillNeedsIt() async {
        let legacy = Data("""
        [{"id":"claude/u-1","handle":"u-1","displayName":"sam@example.com",\
        "refreshToken":"rt-old"}]
        """.utf8)
        let store = await store(WatchfulKeychain([CredentialStore.ownService: legacy]))

        #expect(await store.dependsOnCLI())
    }
}

/// A refresher that can be told the server has finished with the token.
private actor RejectingRefresher: TokenRefreshing {
    private(set) var calls: [String] = []
    private var rejects = false
    func setRejects(_ value: Bool) { rejects = value }

    func refresh(refreshToken: String) async throws -> RefreshedTokens {
        calls.append(refreshToken)
        if rejects { throw RefreshRejected() }
        return RefreshedTokens(accessToken: "fresh", refreshToken: nil)
    }
}

/// An own grant that the server has finished with must not send the account
/// back to the CLI's item.
///
/// When a refresh is finally rejected the token is dropped, which leaves the
/// account marked as an own grant with nothing to refresh. Written as "own grant
/// **and** a token", the branch stopped matching and the account fell through to
/// the CLI path — opening the foreign item again, on every poll, for an account
/// that can only be fixed by signing in. Worse, `dependsOnCLI()` goes on
/// answering `false` for it, so the app would be reading an item it reports it
/// has no reason to touch.
@Suite struct AnOwnGrantTheServerHasFinishedWith {

    private func spentGrant() async throws -> (CredentialStore, WatchfulKeychain) {
        let keychain = WatchfulKeychain([
            CredentialStore.cliService: cliCredentials(token: "cli-tok", refresh: "cli-refresh")
        ])
        let refresher = RejectingRefresher()
        let store = CredentialStore(keychain: keychain, refresher: refresher, cacheWindow: 0)
        await store.load()
        try await store.addLoggedInAccount(
            uuid: "u-1", displayName: "sam@example.com", refreshToken: "rt-web"
        )
        await refresher.setRejects(true)
        _ = try? await store.accessToken(for: "u-1")   // the token is dropped here
        return (store, keychain)
    }

    @Test func itStillNeverOpensTheCLIItem() async throws {
        let (store, keychain) = try await spentGrant()
        let before = await keychain.readCount(for: CredentialStore.cliService)

        _ = try? await store.accessToken(for: "u-1")

        let after = await keychain.readCount(for: CredentialStore.cliService)
        #expect(after == before, """
            a spent own grant opened Claude Code's item \(after - before) time(s) — \
            and dependsOnCLI() reports there is no reason to
            """)
    }

    @Test func andItAsksToBeSignedInto() async throws {
        let (store, _) = try await spentGrant()
        do {
            _ = try await store.accessToken(for: "u-1")
            Issue.record("no failure at all")
        } catch let failure as ProviderFailure {
            #expect(failure.kind == .needsLogin)
        }
    }

    /// The claim and the behaviour have to agree: if nothing depends on the CLI,
    /// nothing may read it.
    @Test func andTheClaimMatches() async throws {
        let (store, _) = try await spentGrant()
        #expect(await store.dependsOnCLI() == false)
    }
}

/// Listing the accounts for the settings screen must not open the CLI's item
/// either, once nothing depends on it.
///
/// `accountStates` asks the CLI which account is active there so it can label
/// one row differently. That question is only worth asking while some account is
/// still a copy taken from the CLI; with every account holding its own grant the
/// answer cannot change any label, and the read is pure cost — the same foreign
/// read the rest of this change exists to stop.
@Suite struct ListingAccountsForTheSettingsScreen {

    @Test func doesNotOpenTheCLIItemWhenNothingDependsOnIt() async throws {
        let keychain = WatchfulKeychain([
            CredentialStore.cliService: cliCredentials(token: "cli-tok", refresh: "cli-refresh")
        ])
        let store = CredentialStore(
            keychain: keychain, refresher: StubRefresher(), cacheWindow: 0
        )
        await store.load()
        try await store.addLoggedInAccount(
            uuid: "u-1", displayName: "sam@example.com", refreshToken: "rt-1"
        )

        _ = await store.accountStates()

        #expect(await keychain.readCount(for: CredentialStore.cliService) == 0)
    }

    /// But it still asks while an account depends on the CLI: that is the only
    /// way to know which row is the active one.
    @Test func stillAsksWhileAnAccountDependsOnIt() async throws {
        let keychain = WatchfulKeychain([
            CredentialStore.cliService: cliCredentials(token: "cli-tok", refresh: "cli-refresh")
        ])
        let store = CredentialStore(
            keychain: keychain, refresher: StubRefresher(), cacheWindow: 0
        )
        await store.load()
        try await store.syncWithCLI(profileUUID: "u-cli", displayName: "cli@example.com")

        let states = await store.accountStates()
        let byHandle = Dictionary(uniqueKeysWithValues: states.map { ($0.account.handle, $0.state) })
        #expect(byHandle["u-cli"] == .activeInCLI)
    }
}
