import Testing
import Foundation
import ProviderKit
import Credentials

private actor DeviceAccounts: KeychainAccess {
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
        Issue.record("a sign-in test must not refresh a credential")
        throw CancellationError()
    }
}

/// A service that answers a scripted sequence, one answer per poll.
///
/// The interval is deliberately tiny: this suite is about the order the loop
/// does things in, not about how long it waits between them.
private actor ScriptedDevice: DeviceCodeAuthenticating {
    nonisolated let provider: ProviderID = .copilot

    private var script: [Result<DeviceCodePoll, any Error>]
    private let lifetime: TimeInterval
    private let codeRequestFails: Bool
    private(set) var polls = 0
    private(set) var codeRequests = 0

    init(
        _ script: [Result<DeviceCodePoll, any Error>],
        lifetime: TimeInterval = 900, codeRequestFails: Bool = false
    ) {
        self.script = script
        self.lifetime = lifetime
        self.codeRequestFails = codeRequestFails
    }

    func requestCode() async throws -> DeviceCodeGrant {
        codeRequests += 1
        if codeRequestFails {
            throw ProviderFailure(kind: .network, diagnostic: "simulated code request failure")
        }
        return DeviceCodeGrant(
            deviceCode: "dev-1", userCode: "WDJB-MJHT",
            verificationURL: URL(string: "https://github.com/login/device")!,
            interval: 0.01, expiresAt: Date().addingTimeInterval(lifetime))
    }

    func poll(_ grant: DeviceCodeGrant) async throws -> DeviceCodePoll {
        polls += 1
        #expect(grant.deviceCode == "dev-1")
        guard !script.isEmpty else { return .pending }
        return try script.removeFirst().get()
    }
}

private func granted() -> DeviceCodePoll {
    .granted(AuthenticatedAccount(
        account: AccountRef(
            id: "copilot/4711", provider: .copilot, handle: "4711", lastKnownName: "sam"),
        // No refresh token and no stated life: the ordinary shape of this
        // grant, and the shape the store has to be willing to keep.
        tokens: RefreshedTokens(accessToken: "gh-token", refreshToken: nil)))
}

@MainActor
private final class Browser {
    var opened: [URL] = []
    private let refuses: Bool

    init(refuses: Bool = false) { self.refuses = refuses }

    func open(_ url: URL) -> Bool {
        opened.append(url)
        return !refuses
    }
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

/// The second shape of sign-in: nothing comes back to us, so the attempt is a
/// code on screen and a loop that keeps asking.
@Suite @MainActor struct DeviceSignIn {

    private func store(_ keychain: DeviceAccounts = DeviceAccounts()) -> CredentialStore {
        CredentialStore(
            keychain: keychain, refresher: NeverRefreshes(), codexRefresher: NeverRefreshes(),
            copilotRefresher: NeverRefreshes())
    }

    private func controller(
        _ device: ScriptedDevice, store: CredentialStore? = nil, browser: Browser = Browser(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> LoginController {
        LoginController(
            store: store ?? self.store(),
            deviceAuthentication: { _ in device },
            openURL: browser.open,
            now: now)
    }

    @Test func theCodeGoesOnScreenAndThePageIsOpened() async throws {
        let browser = Browser()
        let device = ScriptedDevice([.success(.pending)])
        let model = controller(device, browser: browser)

        model.start(provider: .copilot)
        #expect(await eventually { model.deviceGrant != nil })

        #expect(model.deviceGrant?.userCode == "WDJB-MJHT")
        #expect(browser.opened.map(\.absoluteString) == ["https://github.com/login/device"])
        #expect(model.isRunning)
        // The other shape's field must stay shut: this sign-in has no code to
        // paste back, and a field offering to would spend a grant that is not
        // waiting for one.
        #expect(!model.manualCodeExpected)
        model.cancel()
    }

    @Test func waitingThenGrantedSavesTheAccountOnce() async throws {
        let store = store()
        let device = ScriptedDevice([.success(.pending), .success(.pending), .success(granted())])
        let model = controller(device, store: store)

        var completions: [AccountRef] = []
        model.didAddAccount = { ref, origin in
            #expect(!model.isRunning)
            #expect(origin == .settings)
            completions.append(ref)
        }

        model.start(provider: .copilot)
        #expect(await eventually { model.completedSignIns == 1 })

        #expect(completions.map(\.id) == ["copilot/4711"])
        #expect(model.successNotice?.provider == .copilot)
        #expect(model.message == nil)
        #expect(!model.isRunning)
        // The attempt is over, so the code comes off the screen with it.
        #expect(model.deviceGrant == nil)
        #expect(await store.knownRefs().map(\.id) == ["copilot/4711"])
        #expect(await device.polls == 3)

        // And the grant with nothing to rotate is served, which is the whole
        // reason the store learned what a static service is.
        #expect(try await store.accessToken(for: AccountRef(
            id: "copilot/4711", provider: .copilot, handle: "4711")) == "gh-token")
        model.didAddAccount = nil
    }

    @Test func beingToldToSlowDownIsNotAFailure() async throws {
        let store = store()
        let device = ScriptedDevice([.success(.slowDown(0.01)), .success(granted())])
        let model = controller(device, store: store)

        model.start(provider: .copilot)
        #expect(await eventually { model.completedSignIns == 1 })
        #expect(model.message == nil)
        #expect(await store.knownRefs().count == 1)
    }

    @Test func refusingEndsTheAttemptAndSavesNothing() async throws {
        let store = store()
        let device = ScriptedDevice([.failure(DeviceCodeRejected(reason: .denied))])
        let model = controller(device, store: store)

        model.start(provider: .copilot)
        #expect(await eventually { !model.isRunning })
        #expect(model.message != nil)
        #expect(model.deviceGrant == nil)
        #expect(model.completedSignIns == 0)
        #expect(await store.knownRefs().isEmpty)
    }

    /// The deadline is the grant's, not the five minutes a browser attempt
    /// gets — and it is checked before asking, because once the code is stale
    /// the answer cannot change.
    @Test func aStaleCodeStopsBeforeAskingAgain() async throws {
        let clock = MovableClock()
        let store = store()
        let device = ScriptedDevice([.success(.pending)], lifetime: 60)
        let model = controller(device, store: store, now: { clock.reading })

        model.start(provider: .copilot)
        #expect(await eventually { model.deviceGrant != nil })
        clock.advance(by: 3600)

        #expect(await eventually { !model.isRunning })
        #expect(model.message != nil)
        #expect(await store.knownRefs().isEmpty)
    }

    @Test func cancellingStopsTheLoopAndTakesTheCodeDown() async throws {
        let store = store()
        let device = ScriptedDevice([])          // pending forever
        let model = controller(device, store: store)

        model.start(provider: .copilot)
        #expect(await eventually { model.deviceGrant != nil })
        model.cancel()

        #expect(!model.isRunning)
        #expect(model.deviceGrant == nil)
        let stopped = await device.polls
        try await Task.sleep(for: .milliseconds(120))
        #expect(await device.polls == stopped)
        #expect(await store.knownRefs().isEmpty)
    }

    @Test func aFailedCodeRequestEndsTheAttempt() async throws {
        let device = ScriptedDevice([], codeRequestFails: true)
        let model = controller(device)

        model.start(provider: .copilot)
        #expect(await eventually { !model.isRunning })
        #expect(model.message != nil)
        #expect(model.deviceGrant == nil)
    }

    /// A browser that will not open is not fatal here: the address is on
    /// screen and can be typed, so the attempt says so and goes on waiting.
    @Test func aRefusedBrowserLeavesTheCodeUp() async throws {
        let device = ScriptedDevice([.success(.pending)])
        let model = controller(device, browser: Browser(refuses: true))

        model.start(provider: .copilot)
        #expect(await eventually { model.message != nil })
        #expect(model.isRunning)
        #expect(model.deviceGrant != nil)
        model.cancel()
    }

    @Test func aSaveThatFailsIsReportedAndNothingIsClaimed() async throws {
        let store = store(DeviceAccounts(fails: true))
        let device = ScriptedDevice([.success(granted())])
        let model = controller(device, store: store)

        model.start(provider: .copilot)
        #expect(await eventually { !model.isRunning })
        #expect(model.message != nil)
        #expect(model.completedSignIns == 0)
        #expect(model.successNotice == nil)
    }

    /// One attempt at a time, whichever shape it is.
    @Test func aSecondStartWhileOneIsRunningIsIgnored() async throws {
        let device = ScriptedDevice([])
        let model = controller(device)

        model.start(provider: .copilot)
        #expect(await eventually { model.deviceGrant != nil })
        model.start(provider: .claude)

        #expect(model.request?.provider == .copilot)
        #expect(await device.codeRequests == 1)
        model.cancel()
    }

    /// A sign-in the controller will start is a sign-in the store will keep.
    ///
    /// `LoginController.providers` and the store's own list of services it
    /// accepts an account for are two hand-kept lists in two modules, and
    /// nothing makes them agree. Drift shows up at the worst possible moment:
    /// the browser consents, the grant is exchanged, and the save refuses —
    /// a sign-in that worked everywhere except where it counted, and a second
    /// attempt does exactly the same thing.
    ///
    /// Asked as behaviour rather than as a comparison of two lists, because the
    /// store's list is private and because what matters is the account landing,
    /// not the two arrays being spelled alike.
    @Test func everyServiceTheControllerOffersIsOneTheStoreAccepts() async throws {
        for provider in LoginController.providers {
            let store = store()
            await store.load()
            let id = "\(provider.rawValue)/1"
            // Both halves supplied, so this asks about the provider and not
            // about which shape of grant the service happens to issue.
            try await store.addLoggedInAccount(AuthenticatedAccount(
                account: AccountRef(id: id, provider: provider, handle: "1", lastKnownName: "sam"),
                tokens: RefreshedTokens(
                    accessToken: "access", refreshToken: "refresh", expiresIn: 3600)))

            #expect(await store.knownRefs().map(\.id) == [id], """
                the store refused an account for \(provider.rawValue), which \
                LoginController offers a sign-in for
                """)
        }
    }

    /// Two hand-kept lists, and one has to be inside the other.
    ///
    /// `start` refuses a provider absent from `providers`, so a service named
    /// only in `deviceProviders` would have a button in the menu that does
    /// nothing at all — no attempt, no message, no sign that it was pressed.
    @Test func everyDeviceProviderIsOneTheControllerWillStart() {
        #expect(LoginController.deviceProviders
            .isSubset(of: Set(LoginController.providers)))
    }
}

private final class MovableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date()

    var reading: Date {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func advance(by seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        value = value.addingTimeInterval(seconds)
    }
}
