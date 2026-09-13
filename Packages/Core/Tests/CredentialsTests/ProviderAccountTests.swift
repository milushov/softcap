import Testing
import Foundation
import ProviderKit
@testable import Credentials

private actor AccountKeychain: KeychainAccess {
    private var data: Data?
    private(set) var foreignReads = 0
    func read(service: String) throws -> Data? {
        if service != CredentialStore.ownService { foreignReads += 1; return nil }
        return data
    }
    func write(_ data: Data, service: String) throws {
        #expect(service == CredentialStore.ownService)
        self.data = data
    }
}

private actor AccountRefresher: TokenRefreshing {
    private(set) var calls: [String] = []
    private var gate: CheckedContinuation<Void, Never>?
    private let gated: Bool
    private let rejects: Bool
    init(gated: Bool = false, rejects: Bool = false) { self.gated = gated; self.rejects = rejects }
    func refresh(refreshToken: String) async throws -> RefreshedTokens {
        calls.append(refreshToken)
        if gated { await withCheckedContinuation { gate = $0 } }
        if rejects { throw RefreshRejected() }
        return RefreshedTokens(accessToken: "fresh", refreshToken: "rotated", expiresIn: 3600)
    }
    func release() { gate?.resume(); gate = nil }
}

private func grant(_ provider: ProviderID, refresh: String = "refresh", expires: TimeInterval? = nil) -> AuthenticatedAccount {
    AuthenticatedAccount(account: AccountRef(
        id: "\(provider.rawValue)/same", provider: provider, handle: "same", lastKnownName: "sam@example.com"),
        tokens: RefreshedTokens(accessToken: "initial", refreshToken: refresh, expiresIn: expires))
}

private func waitForCall(_ service: AccountRefresher) async -> Bool {
    for _ in 0..<1000 {
        if await !service.calls.isEmpty { return true }
        await Task.yield()
    }
    return false
}

@Suite struct ProviderAccountIsolation {
    @Test func equalHandlesAreDistinctAndRefreshAtTheCorrectService() async throws {
        let keychain = AccountKeychain()
        let claude = AccountRefresher()
        let codex = AccountRefresher()
        let store = CredentialStore(keychain: keychain, refresher: claude, codexRefresher: codex)
        try await store.addLoggedInAccount(grant(.claude, refresh: "claude"))
        try await store.addLoggedInAccount(grant(.codex, refresh: "codex"))
        #expect(Set(await store.knownRefs().map(\.id)) == ["claude/same", "codex/same"])
        _ = try await store.accessToken(for: grant(.codex).account)
        #expect(await codex.calls == ["codex"])
        #expect(await claude.calls.isEmpty)
        _ = try await store.accessToken(for: "same")
        #expect(await claude.calls == ["claude"])
        #expect(await keychain.foreignReads == 0)
        try await store.forget(id: "codex/same")
        #expect(await store.knownRefs().map(\.id) == ["claude/same"])
    }

    @Test func firstUsageAndRelaunchReuseTheLoginAccessToken() async throws {
        let keychain = AccountKeychain()
        let refresh = AccountRefresher()
        let store = CredentialStore(keychain: keychain, refresher: refresh, codexRefresher: refresh)
        try await store.addLoggedInAccount(grant(.codex, expires: 3600))
        #expect(try await store.accessToken(for: grant(.codex).account) == "initial")
        let reopened = CredentialStore(keychain: keychain, refresher: refresh, codexRefresher: refresh)
        await reopened.load()
        #expect(try await reopened.accessToken(for: grant(.codex).account) == "initial")
        #expect(await refresh.calls.isEmpty)
        let states = await reopened.accountStates()
        #expect(states.first?.state == .refreshed)
        #expect(await keychain.foreignReads == 0)
    }

    @Test func oldKeychainFormatStillDecodesAsClaude() throws {
        let data = Data(#"[{"id":"claude/same","handle":"same","displayName":"Sam","refreshToken":"old"}]"#.utf8)
        let account = try #require(JSONDecoder().decode([StoredAccount].self, from: data).first)
        #expect(account.provider == .claude)
        #expect(!account.isOwnGrant)
    }

    @Test(arguments: [false, true]) func oldRefreshCannotOverwriteOrEraseANewSignIn(rejected: Bool) async throws {
        let keychain = AccountKeychain()
        let gate = AccountRefresher(gated: true, rejects: rejected)
        let store = CredentialStore(keychain: keychain, refresher: gate, codexRefresher: gate)
        try await store.addLoggedInAccount(grant(.codex, refresh: "old"))
        let pending = Task { try await store.accessToken(for: grant(.codex).account) }
        #expect(await waitForCall(gate))
        try await store.addLoggedInAccount(grant(.codex, refresh: "new", expires: 3600))
        await gate.release()
        _ = await pending.result
        #expect(try await store.accessToken(for: grant(.codex).account) == "initial")
        let saved = try #require(await keychain.read(service: CredentialStore.ownService))
        #expect(try JSONDecoder().decode([StoredAccount].self, from: saved).first?.refreshToken == "new")
    }

    @Test func rejectedCodexGrantNeverFallsBackToClaudeKeychain() async throws {
        let keychain = AccountKeychain()
        let reject = AccountRefresher(rejects: true)
        let store = CredentialStore(keychain: keychain, refresher: reject, codexRefresher: reject)
        try await store.addLoggedInAccount(grant(.codex))
        for _ in 0..<2 {
            await #expect(throws: ProviderFailure.self) { try await store.accessToken(for: grant(.codex).account) }
        }
        #expect(await reject.calls.count == 1)
        #expect(await keychain.foreignReads == 0)
        let states = await store.accountStates()
        #expect(states.first?.state == .needsLogin)
    }

    @Test func invalidatingAnOldAccessTokenDoesNotDiscardANewerOne() async throws {
        let keychain = AccountKeychain()
        let refresh = AccountRefresher()
        let store = CredentialStore(keychain: keychain, refresher: refresh, codexRefresher: refresh)
        try await store.addLoggedInAccount(grant(.codex, expires: 3600))
        await store.invalidateAccessToken(for: grant(.codex).account, rejectedToken: "old")
        #expect(try await store.accessToken(for: grant(.codex).account) == "initial")
        #expect(await refresh.calls.isEmpty)
    }
}
