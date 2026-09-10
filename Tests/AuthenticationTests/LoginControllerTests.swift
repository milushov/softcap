import Testing
import Foundation
import ProviderKit
import Credentials

private actor MemoryAccounts: KeychainAccess {
    private var data: Data?
    func read(service: String, promptIfNeeded: Bool) throws -> Data? { data }
    func write(_ data: Data, service: String) throws { self.data = data }
}

private struct NoRefresh: TokenRefreshing {
    func refresh(refreshToken: String) async throws -> RefreshedTokens {
        Issue.record("a sign-in test must not refresh a credential")
        throw CancellationError()
    }
}

private actor BrowserAuth: BrowserAuthenticating {
    nonisolated let provider: ProviderID = .codex
    nonisolated let callbackPath = "/auth/callback"
    nonisolated let callbackPort: UInt16?
    nonisolated let manualRedirectURI: String?
    private let gated: Bool
    private var pending: CheckedContinuation<Void, Never>?
    private(set) var calls = 0

    init(port: UInt16? = nil, manual: String? = nil, gated: Bool = false) {
        callbackPort = port
        manualRedirectURI = manual
        self.gated = gated
    }
    nonisolated func authorizationURL(
        redirectURI: String, pkce: PKCEPair, state: String, manual: Bool
    ) -> URL {
        var parts = URLComponents(string: redirectURI)!
        parts.queryItems = [URLQueryItem(name: "state", value: state), URLQueryItem(name: "code", value: "reply")]
        return parts.url!
    }
    func authenticate(code: String, verifier: String, redirectURI: String, state: String) async throws -> AuthenticatedAccount {
        calls += 1
        if gated { await withCheckedContinuation { pending = $0 } }
        return AuthenticatedAccount(account: AccountRef(
            id: "codex/example", provider: .codex, handle: "example", lastKnownName: "sam@example.com"),
            tokens: RefreshedTokens(accessToken: "access", refreshToken: "refresh", expiresIn: 3600))
    }
    func release() { pending?.resume(); pending = nil }
}

@MainActor
private final class Browser {
    var url: URL?
    func open(_ url: URL) -> Bool { self.url = url; return true }
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

@Suite @MainActor struct BrowserLoginLifecycle {
    private func store() -> CredentialStore {
        CredentialStore(keychain: MemoryAccounts(), refresher: NoRefresh(), codexRefresher: NoRefresh())
    }

    @Test func cancelBeforeListenerStartsNeverOpensBrowser() async throws {
        let browser = Browser()
        let auth = BrowserAuth()
        let model = LoginController(store: store(), authentication: { _ in auth }, openURL: browser.open)
        model.start(provider: .codex)
        model.cancel()
        try await Task.sleep(for: .milliseconds(50))
        #expect(browser.url == nil)
        #expect(!model.isRunning)
        #expect(model.message == nil)
    }

    @Test func realLoopbackCallbackAddsAccountOnlyOnce() async throws {
        let browser = Browser()
        let auth = BrowserAuth()
        let store = store()
        let model = LoginController(store: store, authentication: { _ in auth }, openURL: browser.open)
        model.start(provider: .codex)
        #expect(await eventually { browser.url != nil })
        let url = try #require(browser.url)
        let (body, response) = try await URLSession.shared.data(from: url)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(!body.isEmpty)
        #expect(await eventually { model.completedSignIns == 1 })
        #expect(await auth.calls == 1)
        #expect(await store.knownRefs().map(\.id) == ["codex/example"])
        #expect(!model.isRunning)
    }

    @Test func aForeignCallbackDoesNotCancelTheRealAttempt() async throws {
        let browser = Browser()
        let auth = BrowserAuth()
        let model = LoginController(store: store(), authentication: { _ in auth }, openURL: browser.open)
        model.start(provider: .codex)
        #expect(await eventually { browser.url != nil })
        let url = try #require(browser.url)
        var wrong = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        wrong.queryItems = [URLQueryItem(name: "state", value: "other"), URLQueryItem(name: "code", value: "reply")]
        _ = try await URLSession.shared.data(from: try #require(wrong.url))
        #expect(model.isRunning)
        #expect(await auth.calls == 0)
        _ = try await URLSession.shared.data(from: try #require(browser.url))
        #expect(await eventually { model.completedSignIns == 1 })
    }

    @Test func cancelDuringExchangeDoesNotSaveOrFinishALaterAttempt() async throws {
        let browser = Browser()
        let auth = BrowserAuth(gated: true)
        let store = store()
        let model = LoginController(store: store, authentication: { _ in auth }, openURL: browser.open)
        model.start(provider: .codex)
        #expect(await eventually { browser.url != nil })
        _ = try await URLSession.shared.data(from: try #require(browser.url))
        #expect(await eventually { await auth.calls == 1 })
        model.cancel()
        browser.url = nil
        model.start(provider: .codex)
        #expect(await eventually { browser.url != nil })
        await auth.release()
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.isRunning)
        #expect(model.completedSignIns == 0)
        #expect(await store.knownRefs().isEmpty)
        model.cancel()
    }

    @Test func timeoutEndsTheAttemptAndAllowsRetry() async throws {
        let auth = BrowserAuth()
        let browser = Browser()
        let model = LoginController(store: store(), authentication: { _ in auth }, openURL: browser.open,
                                    timeoutDuration: .milliseconds(50))
        model.start(provider: .codex)
        #expect(await eventually { !model.isRunning })
        #expect(model.message != nil)
        #expect(!model.manualCodeExpected)
        model.start(provider: .codex)
        #expect(model.isRunning)
        model.cancel()
    }

    @Test func failedBrowserLaunchEndsTheAttempt() async throws {
        let auth = BrowserAuth()
        let model = LoginController(store: store(), authentication: { _ in auth }, openURL: { _ in false })
        model.start(provider: .codex)
        #expect(await eventually { !model.isRunning })
        #expect(model.message != nil)
    }

    @Test func occupiedPortIsAnErrorForCodexAndManualFallbackForClaude() async throws {
        let occupied = BrowserCallbackListener()
        let port = try await occupied.start(port: nil) { _, connection in connection.cancel() }
        defer { occupied.stop() }
        let browser = Browser()
        let codex = BrowserAuth(port: port)
        let first = LoginController(store: store(), authentication: { _ in codex }, openURL: browser.open)
        first.start(provider: .codex)
        #expect(await eventually { !first.isRunning })
        #expect(browser.url == nil)
        #expect(!first.manualCodeExpected)
        #expect(first.message != nil)

        let claude = BrowserAuth(port: port, manual: "http://localhost/callback")
        let second = LoginController(store: store(), authentication: { _ in claude }, openURL: browser.open)
        second.start(provider: .claude)
        #expect(await eventually { second.manualCodeExpected })
        #expect(browser.url != nil)
        second.cancel()
        await second.submit(code: "reply")
        #expect(await claude.calls == 0)
        #expect(!second.manualCodeExpected)
    }
}
