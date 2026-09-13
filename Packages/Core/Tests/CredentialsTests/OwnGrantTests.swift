import Testing
import Foundation
import ProviderKit
import ClaudeProvider
@testable import Credentials

/// A keychain that remembers which items were asked for.
///
/// The question these tests ask is not "what came back" but "what was touched".
/// Reading any item this app does not own is what used to cost something: macOS
/// checks a foreign item against its access list on every read, and the dialog
/// that grants the read is the one people were meeting on every update.
private actor WatchfulKeychain: KeychainAccess {
    private var items: [String: Data] = [:]
    private(set) var servicesRead: [String] = []

    init(_ seed: [String: Data] = [:]) { items = seed }

    func read(service: String) throws -> Data? {
        servicesRead.append(service)
        return items[service]
    }
    func write(_ data: Data, service: String) throws { items[service] = data }

    func seed(_ data: Data, service: String) { items[service] = data }
    func readCount(for service: String) -> Int { servicesRead.filter { $0 == service }.count }
    var foreignReads: [String] { servicesRead.filter { $0 != CredentialStore.ownService } }
}

private actor StubRefresher: TokenRefreshing {
    private(set) var calls: [String] = []
    func refresh(refreshToken: String) async throws -> RefreshedTokens {
        calls.append(refreshToken)
        return RefreshedTokens(accessToken: "fresh-for-\(refreshToken)", refreshToken: nil)
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

/// The store opens one keychain item and no other.
///
/// This replaces a suite of tests that each named `Claude Code-credentials` and
/// checked it had been left alone. Naming the item was the weakness: it proved
/// only that one particular foreign item went untouched, and the reason the
/// reads were costly — macOS re-checks a foreign item's access list on every
/// read, and its owner rewrites the list whenever it refreshes — applies to any
/// item this app does not own. Asking "was anything else opened at all" is the
/// claim actually worth holding, and it cannot be satisfied by a build that
/// starts reading some *other* app's credentials instead.
@Suite struct TheStoreTouchesItsOwnItemOnly {

    @Test func acrossSigningIn() async throws {
        let keychain = WatchfulKeychain()
        let store = CredentialStore(keychain: keychain, refresher: StubRefresher())
        await store.load()
        try await store.addLoggedInAccount(
            uuid: "u-1", displayName: "sam@example.com", refreshToken: "rt-web"
        )

        let foreign = await keychain.foreignReads
        #expect(foreign.isEmpty, """
            the store read \(foreign) — every read of an item this app does not \
            own is a permission dialog waiting to happen
            """)
    }

    @Test func acrossRepeatedPolls() async throws {
        let keychain = WatchfulKeychain()
        let store = CredentialStore(keychain: keychain, refresher: StubRefresher())
        await store.load()
        try await store.addLoggedInAccount(
            uuid: "u-1", displayName: "sam@example.com", refreshToken: "rt-web"
        )
        for _ in 0..<3 { _ = try? await store.accessToken(for: "u-1") }

        let foreign = await keychain.foreignReads
        #expect(foreign.isEmpty)
    }

    @Test func andWhileListingAccountsForTheSettingsScreen() async throws {
        let keychain = WatchfulKeychain()
        let store = CredentialStore(keychain: keychain, refresher: StubRefresher())
        await store.load()
        try await store.addLoggedInAccount(
            uuid: "u-1", displayName: "sam@example.com", refreshToken: "rt-web"
        )
        _ = await store.accountStates()

        let foreign = await keychain.foreignReads
        #expect(foreign.isEmpty)
    }
}

@Suite struct AnAccountWithNoCredentialAsksToBeSignedInto {

    @Test func itSaysSignIn() async throws {
        let refresher = RejectingRefresher()
        let store = CredentialStore(keychain: WatchfulKeychain(), refresher: refresher)
        try await store.addLoggedInAccount(
            uuid: "u-1", displayName: "sam@example.com", refreshToken: "rt-web"
        )
        await refresher.setRejects(true)
        // The server finishes with the credential: this attempt drops it, which
        // is how an account comes to have nothing of its own.
        _ = try? await store.accessToken(for: "u-1")

        do {
            _ = try await store.accessToken(for: "u-1")
            Issue.record("no failure at all")
        } catch let failure as ProviderFailure {
            #expect(failure.kind == .needsLogin, """
                reported \(failure.kind) — the row would ask for something other \
                than the sign-in that is the only way back
                """)
        }
    }

    /// And the row says so on the settings screen, rather than claiming a
    /// reading that can never arrive.
    @Test func andTheRowSaysSoToo() async throws {
        let refresher = RejectingRefresher()
        let store = CredentialStore(keychain: WatchfulKeychain(), refresher: refresher)
        try await store.addLoggedInAccount(
            uuid: "u-1", displayName: "sam@example.com", refreshToken: "rt-web"
        )
        await refresher.setRejects(true)
        _ = try? await store.accessToken(for: "u-1")

        let states = await store.accountStates()
        #expect(states.first?.state == .needsLogin)
    }
}

/// A list written by a build that predates `tokenOrigin` must still decode.
///
/// `StoredAccount` decodes through the synthesised `Codable`, which refuses a
/// blob missing any non-optional field. The item holds the only copy of every
/// account's refresh token, and `load` treats an undecodable item as "present
/// but unreadable" — which then refuses every write to protect it. A required
/// new field would put every existing install in that state at once: no
/// accounts in the window, and no way to add any.
@Suite struct AListWrittenBeforeOriginsWereRecorded {

    private static let legacy = Data("""
    [{"id":"claude/u-1","handle":"u-1","displayName":"sam@example.com",\
    "refreshToken":"cli-refresh"}]
    """.utf8)

    @Test func stillDecodes() async throws {
        let keychain = WatchfulKeychain([CredentialStore.ownService: Self.legacy])
        let store = CredentialStore(keychain: keychain, refresher: StubRefresher())
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
        let keychain = WatchfulKeychain([CredentialStore.ownService: Self.legacy])
        let store = CredentialStore(keychain: keychain, refresher: StubRefresher())
        await store.load()

        try await store.addLoggedInAccount(
            uuid: "u-2", displayName: "alex@example.com", refreshToken: "rt-new"
        )
        #expect(await store.knownRefs().count == 2)
    }

    /// Such an account has no recorded origin, and the only origin it could have
    /// had is Claude Code: the browser path is what introduced the field. Its
    /// "refresh token" is therefore a copy of the CLI's own, and spending one
    /// rotates it server side — signing Claude Code out. The app used to be able
    /// to read the CLI's item and see what it was doing; it no longer can, so
    /// the only safe move is to refuse and ask for a browser sign-in.
    @Test func itsTokenIsNeverSpent() async throws {
        let keychain = WatchfulKeychain([CredentialStore.ownService: Self.legacy])
        let refresher = StubRefresher()
        let store = CredentialStore(keychain: keychain, refresher: refresher)
        await store.load()

        do {
            _ = try await store.accessToken(for: "u-1")
            Issue.record("the copied token was spent")
        } catch let failure as ProviderFailure {
            #expect(failure.kind == .needsLogin)
        }
        #expect(await refresher.calls.isEmpty, """
            a token copied from Claude Code was sent to be refreshed — the server \
            rotates it on use, which signs the CLI out
            """)
    }

    /// And the row asks for the sign-in that fixes it, rather than showing a
    /// state that promises a reading.
    @Test func andTheRowAsksForASignIn() async throws {
        let keychain = WatchfulKeychain([CredentialStore.ownService: Self.legacy])
        let store = CredentialStore(keychain: keychain, refresher: StubRefresher())
        await store.load()

        let states = await store.accountStates()
        #expect(states.first?.state == .needsLogin)
    }
}
