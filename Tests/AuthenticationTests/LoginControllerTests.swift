import Testing
import Foundation
import ProviderKit
import Credentials

private actor MemoryAccounts: KeychainAccess {
    private var data: Data?
    private let gated: Bool
    private let fails: Bool
    private var pending: CheckedContinuation<Void, Never>?
    private(set) var writes = 0

    init(gated: Bool = false, fails: Bool = false) {
        self.gated = gated
        self.fails = fails
    }

    func read(service: String) throws -> Data? { data }
    func write(_ data: Data, service: String) async throws {
        writes += 1
        if gated { await withCheckedContinuation { pending = $0 } }
        if fails { throw ProviderFailure(kind: .needsLogin, diagnostic: "simulated persistence failure") }
        self.data = data
    }
    func release() { pending?.resume(); pending = nil }
}

private struct NoRefresh: TokenRefreshing {
    func refresh(refreshToken: String) async throws -> RefreshedTokens {
        Issue.record("a sign-in test must not refresh a credential")
        throw CancellationError()
    }
}

private actor BrowserAuth: BrowserAuthenticating {
    nonisolated let provider: ProviderID
    nonisolated let callbackPath: String
    nonisolated let callbackPort: UInt16?
    nonisolated let manualRedirectURI: String?
    private let gated: Bool
    private let fails: Bool
    private var pending: CheckedContinuation<Void, Never>?
    private(set) var calls = 0

    init(provider: ProviderID = .codex, port: UInt16? = nil, manual: String? = nil,
         gated: Bool = false, fails: Bool = false) {
        self.provider = provider
        callbackPath = provider == .codex ? "/auth/callback" : "/callback"
        callbackPort = port
        manualRedirectURI = manual
        self.gated = gated
        self.fails = fails
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
        if fails { throw ProviderFailure(kind: .network, diagnostic: "simulated exchange failure") }
        return AuthenticatedAccount(account: AccountRef(
            id: "\(provider.rawValue)/example", provider: provider, handle: "example", lastKnownName: "sam@example.com"),
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
    private func store(keychain: MemoryAccounts = MemoryAccounts()) -> CredentialStore {
        CredentialStore(keychain: keychain, refresher: NoRefresh(), codexRefresher: NoRefresh())
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

    @Test(arguments: [ProviderID.claude, .codex])
    func realLoopbackCallbackAddsAccountOnlyOnce(provider: ProviderID) async throws {
        let browser = Browser()
        let auth = BrowserAuth(provider: provider)
        let store = store()
        let model = LoginController(store: store, authentication: { _ in auth }, openURL: browser.open)
        var completions: [AccountRef] = []
        model.didAddAccount = { ref, _ in
            #expect(!model.isRunning)
            #expect(model.successNotice == ref)
            completions.append(ref)
        }
        model.start(provider: provider)
        #expect(await eventually { browser.url != nil })
        let url = try #require(browser.url)
        let (body, response) = try await URLSession.shared.data(from: url)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: body, as: UTF8.self).contains("window.close()"))
        #expect(await eventually { model.completedSignIns == 1 })
        #expect(await auth.calls == 1)
        #expect(await store.knownRefs().map(\.id) == ["\(provider.rawValue)/example"])
        #expect(completions.map(\.provider) == [provider])
        #expect(model.successNotice?.provider == provider)
        #expect(model.message == nil)
        #expect(!model.isRunning)
        model.dismissSuccessNotice()
        #expect(model.successNotice == nil)
        #expect(model.completedSignIns == 1)
        model.didAddAccount = nil
    }

    @Test func browserAndAppWaitForPersistence() async throws {
        let browser = Browser()
        let auth = BrowserAuth()
        let keychain = MemoryAccounts(gated: true)
        let model = LoginController(store: store(keychain: keychain), authentication: { _ in auth }, openURL: browser.open)
        var completions = 0
        model.didAddAccount = { _, _ in completions += 1 }
        model.start(provider: .codex)
        #expect(await eventually { browser.url != nil })
        let url = try #require(browser.url)
        var browserReplied = false
        let response = Task {
            let result = try await URLSession.shared.data(from: url)
            browserReplied = true
            return result
        }
        #expect(await eventually { await keychain.writes == 1 })
        try await Task.sleep(for: .milliseconds(50))
        #expect(!browserReplied)
        #expect(model.isRunning)
        #expect(model.isSavingAccount)
        #expect(model.successNotice == nil)
        #expect(model.completedSignIns == 0)
        #expect(completions == 0)
        await keychain.release()
        let (body, reply) = try await response.value
        #expect((reply as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: body, as: UTF8.self).contains("window.close()"))
        #expect(completions == 1)
        #expect(model.successNotice != nil)

        model.start(provider: .codex)
        #expect(model.successNotice == nil)
        model.cancel()
    }

    @Test(arguments: [false, true])
    func failedExchangeOrSaveNeverClosesBrowserOrSignalsSuccess(saveFails: Bool) async throws {
        let browser = Browser()
        let auth = BrowserAuth(fails: !saveFails)
        let store = store(keychain: MemoryAccounts(fails: saveFails))
        let model = LoginController(store: store, authentication: { _ in auth }, openURL: browser.open)
        var completions = 0
        model.didAddAccount = { _, _ in completions += 1 }
        model.start(provider: .codex)
        #expect(await eventually { browser.url != nil })
        let (body, response) = try await URLSession.shared.data(from: try #require(browser.url))
        #expect((response as? HTTPURLResponse)?.statusCode == 400)
        #expect(!String(decoding: body, as: UTF8.self).contains("window.close()"))
        #expect(!model.isRunning)
        #expect(model.message != nil)
        #expect(model.successNotice == nil)
        #expect(model.completedSignIns == 0)
        #expect(completions == 0)
        #expect(await store.knownRefs().isEmpty)
    }

    @Test(arguments: [false, true])
    func cancellationAndTimeoutCannotContradictAnInFlightSave(saveFails: Bool) async throws {
        let browser = Browser()
        let auth = BrowserAuth()
        let keychain = MemoryAccounts(gated: true, fails: saveFails)
        let store = store(keychain: keychain)
        let model = LoginController(store: store, authentication: { _ in auth }, openURL: browser.open,
                                    timeoutDuration: .seconds(1))
        var completions = 0
        model.didAddAccount = { _, _ in completions += 1 }
        model.start(provider: .codex)
        #expect(await eventually { browser.url != nil })
        let url = try #require(browser.url)
        let response = Task { try await URLSession.shared.data(from: url) }
        #expect(await eventually { await keychain.writes == 1 })

        // A keychain write already under way cannot be cancelled. Neither a
        // click nor the browser timer may report failure and permit a retry
        // while that write can still commit the previous account.
        model.cancel()
        model.start(provider: .claude)
        try await Task.sleep(for: .milliseconds(1100))
        #expect(model.isRunning)
        #expect(model.provider == .codex)
        #expect(model.message == nil)
        #expect(model.successNotice == nil)
        #expect(completions == 0)
        await keychain.release()

        let (body, reply) = try await response.value
        #expect((reply as? HTTPURLResponse)?.statusCode == (saveFails ? 400 : 200))
        #expect(String(decoding: body, as: UTF8.self).contains("window.close()") == !saveFails)
        #expect(!model.isRunning)
        #expect((model.successNotice != nil) == !saveFails)
        #expect(!model.isSavingAccount)
        #expect(completions == (saveFails ? 0 : 1))
        #expect(await store.knownRefs().isEmpty == saveFails)
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
        let (body, response) = try await URLSession.shared.data(from: try #require(wrong.url))
        #expect((response as? HTTPURLResponse)?.statusCode == 400)
        #expect(!String(decoding: body, as: UTF8.self).contains("window.close()"))
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
        var completions = 0
        model.didAddAccount = { _, _ in completions += 1 }
        model.start(provider: .codex)
        #expect(await eventually { browser.url != nil })
        let url = try #require(browser.url)
        let response = Task { try await URLSession.shared.data(from: url) }
        #expect(await eventually { await auth.calls == 1 })
        model.cancel()
        let (body, reply) = try await response.value
        #expect((reply as? HTTPURLResponse)?.statusCode == 400)
        #expect(!String(decoding: body, as: UTF8.self).contains("window.close()"))
        browser.url = nil
        model.start(provider: .codex)
        #expect(await eventually { browser.url != nil })
        await auth.release()
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.isRunning)
        #expect(model.completedSignIns == 0)
        #expect(model.successNotice == nil)
        #expect(completions == 0)
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

        let claude = BrowserAuth(provider: .claude, port: port, manual: "http://localhost/callback")
        let second = LoginController(store: store(), authentication: { _ in claude }, openURL: browser.open)
        second.start(provider: .claude)
        #expect(await eventually { second.manualCodeExpected })
        #expect(browser.url != nil)
        second.cancel()
        await second.submit(code: "reply")
        #expect(await claude.calls == 0)
        #expect(!second.manualCodeExpected)
    }

    @Test func manualClaudeCompletionStillSignalsTheApp() async throws {
        let occupied = BrowserCallbackListener()
        let port = try await occupied.start(port: nil) { _, connection in connection.cancel() }
        defer { occupied.stop() }
        let browser = Browser()
        let auth = BrowserAuth(provider: .claude, port: port, manual: "http://localhost/callback", gated: true)
        let model = LoginController(store: store(), authentication: { _ in auth }, openURL: browser.open)
        var completions: [AccountRef] = []
        model.didAddAccount = { account, _ in completions.append(account) }
        model.start(provider: .claude)
        #expect(await eventually { model.manualCodeExpected && browser.url != nil })
        await model.submit(code: "reply")
        #expect(await eventually { await auth.calls == 1 })
        #expect(!model.manualCodeExpected)
        #expect(model.message == nil)
        await auth.release()
        #expect(await eventually { model.completedSignIns == 1 })
        #expect(completions.map(\.provider) == [.claude])
        #expect(model.successNotice?.provider == .claude)
        #expect(!model.isRunning)
    }

    /// A sign-in remembers which screen asked for it, and says so when it is
    /// done.
    ///
    /// Success used to open the settings window whichever screen had started
    /// the attempt — correct while that screen was the only one with the button
    /// on it. The limits window has one now, in the row that says the token is
    /// dead, and the whole point of that button is not having to go to
    /// settings. Without the origin travelling with the account, pressing it
    /// would end by opening the screen it exists to replace.
    ///
    /// The row travels too. Two accounts of one service can be dead at once and
    /// only one of them asked, so the window has to know which of its rows to
    /// draw the attempt on.
    @Test(arguments: [SignInOrigin.settings, .window])
    func theAnswerGoesBackToWhicheverScreenAsked(origin: SignInOrigin) async throws {
        let browser = Browser()
        let auth = BrowserAuth(provider: .claude)
        let model = LoginController(store: store(), authentication: { _ in auth }, openURL: browser.open)
        var reported: [SignInOrigin] = []
        model.didAddAccount = { _, origin in reported.append(origin) }

        model.start(provider: .claude, from: origin, for: "claude/asked")
        #expect(model.request == SignInRequest(
            provider: .claude, origin: origin, account: "claude/asked"))

        #expect(await eventually { browser.url != nil })
        let url = try #require(browser.url)
        _ = try await URLSession.shared.data(from: url)
        #expect(await eventually { model.completedSignIns == 1 })
        #expect(reported == [origin])

        // And it is still readable afterwards. The attempt is torn down before
        // the window is redrawn, and `message` outlives it — a window that lost
        // the request along with the attempt could not say which of its rows a
        // failed sign-in's sentence belongs to.
        #expect(!model.isRunning)
        #expect(model.request?.account == "claude/asked")
    }

    /// "Add account…" asks for no particular row, and must not be mistaken for
    /// one. `nil` matched against a row identifier is false everywhere, which is
    /// what makes every row leave that attempt alone.
    @Test func addingAnAccountClaimsNoRow() async throws {
        let model = LoginController(store: store(), authentication: { _ in BrowserAuth() },
                                    openURL: Browser().open)
        model.start(provider: .codex)
        #expect(model.request?.origin == .settings)
        #expect(model.request?.account == nil)
        model.cancel()
    }

    @Test func timeoutDuringExchangeReleasesBrowserWithoutSuccess() async throws {
        let browser = Browser()
        let auth = BrowserAuth(gated: true)
        let model = LoginController(store: store(), authentication: { _ in auth }, openURL: browser.open,
                                    timeoutDuration: .seconds(1))
        var completions = 0
        model.didAddAccount = { _, _ in completions += 1 }
        model.start(provider: .codex)
        #expect(await eventually { browser.url != nil })
        let url = try #require(browser.url)
        let response = Task { try await URLSession.shared.data(from: url) }
        #expect(await eventually { await auth.calls == 1 })
        let (body, reply) = try await response.value
        #expect((reply as? HTTPURLResponse)?.statusCode == 400)
        #expect(!String(decoding: body, as: UTF8.self).contains("window.close()"))
        await auth.release()
        #expect(!model.isRunning)
        #expect(model.message != nil)
        #expect(model.successNotice == nil)
        #expect(completions == 0)
    }
}
