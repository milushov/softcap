import Foundation
import AppKit
import OSLog
import Network
import ProviderKit
import ClaudeProvider
import CodexProvider
import CopilotProvider
import ZaiProvider
import Credentials
import Diagnostics
import StatusUI

/// Which screen asked for a sign-in.
///
/// It decides where the answer goes. Success used to open the settings window
/// unconditionally, which was right while settings was the only screen with the
/// button on it — a sign-in started from the limits window would otherwise
/// finish by opening the screen the window exists to save a trip to.
enum SignInOrigin: Sendable, Hashable {
    case settings
    case window
}

/// One sign-in, as asked for: which service, from where, and — when a row
/// asked rather than "Add account…" — which row.
///
/// The row matters because the window draws several and only one of them asked.
/// Without it the spinner would have to go on every account of that service, or
/// on none.
struct SignInRequest: Sendable, Hashable {
    let provider: ProviderID
    let origin: SignInOrigin
    let account: String?
}

/// Owns one browser attempt. Protocol details and identity resolution belong to
/// the provider; cancellation invalidates the attempt before cancelling its work.
@MainActor
final class LoginController: ObservableObject {
    static let providers: [ProviderID] = [.claude, .codex, .copilot, .glm]

    /// Which of them sign in by carrying a code rather than by catching a
    /// redirect. Named here rather than asked of the provider, because the
    /// question is "which screen does this need", and the screen is this
    /// layer's to know.
    static let deviceProviders: Set<ProviderID> = [.copilot]

    /// And which are signed into by handing a key over. A third shape, and the
    /// only one with nothing running in it: until the person types, there is no
    /// attempt in flight, no deadline and nothing to cancel but the waiting.
    static let keyProviders: Set<ProviderID> = [.glm]
    @Published private(set) var isRunning = false
    @Published private(set) var isSavingAccount = false

    /// The sign-in most recently asked for. One value rather than a published
    /// field per part: they are set together, and three that could disagree
    /// are three that eventually will.
    ///
    /// It outlives its attempt, and `isRunning` is what says whether one is
    /// still in hand. `message` outlives the attempt too — it has to, or a
    /// sign-in that failed leaves the row saying exactly what it said before
    /// anybody pressed anything — and a window drawing four rows needs to know
    /// which of them that sentence is about.
    @Published private(set) var request: SignInRequest?

    /// Kept for the screens that only ever wanted the service. Read under
    /// `isRunning`, which is the only reading of it that means anything.
    var provider: ProviderID? { request?.provider }

    @Published private(set) var message: String?
    @Published private(set) var manualCodeExpected = false

    /// The code to show and the page to send somebody to, while a device
    /// sign-in is waiting on them. `nil` at every other moment, which is what
    /// the screen reads to decide whether to draw it at all.
    @Published private(set) var deviceGrant: DeviceCodeGrant?

    /// Whether a screen should be offering a field for a key.
    ///
    /// Read beside `isRunning` rather than instead of it: an attempt is in hand
    /// — the menu stays shut, cancelling works — but nothing is happening, so
    /// the screen shows a field and no spinner. A spinner turning while it
    /// waits for somebody to paste says the app is doing something, and it is
    /// not.
    @Published private(set) var keyExpected = false
    @Published private(set) var completedSignIns = 0
    @Published private(set) var successNotice: AccountRef?

    /// The origin travels with the account because the attempt is torn down
    /// before this is called — `finish` ends it, and then reports. A handler
    /// reading `request` here would read `nil` every time.
    var didAddAccount: (@MainActor (AccountRef, SignInOrigin) -> Void)?

    private static let log = Logger(subsystem: "app.softcap.Softcap", category: "login")
    private let store: CredentialStore
    private let keyAuthentication: @Sendable (ProviderID) -> any KeyAuthenticating
    private let authentication: @Sendable (ProviderID) -> any BrowserAuthenticating
    private let deviceAuthentication: @Sendable (ProviderID) -> any DeviceCodeAuthenticating
    private let openURL: @MainActor (URL) -> Bool
    private let timeoutDuration: Duration
    private let now: @Sendable () -> Date
    private var listener: BrowserCallbackListener?
    private var operation: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var attempt: Attempt?
    /// The other shape's attempt. Two fields rather than one because they hold
    /// different things — one carries a verifier, a state and a redirect, the
    /// other carries nothing but its own identity — and only ever one at a
    /// time: `start` refuses while `isRunning`, which is the single answer to
    /// whether an attempt is in hand.
    private var deviceAttempt: DeviceAttempt?
    private var exchanging = false
    private var pendingBrowserReply: NWConnection?

    private struct DeviceAttempt {
        let id = UUID()
        let request: SignInRequest
    }

    /// The third shape's attempt. It holds nothing but its identity, because
    /// there is nothing to hold: the credential arrives from the screen.
    private var keyAttempt: KeyAttempt?

    private struct KeyAttempt {
        let id = UUID()
        let request: SignInRequest
    }

    private struct Attempt {
        let id = UUID()
        let authentication: any BrowserAuthenticating
        let pair: PKCEPair
        let state: String
        let request: SignInRequest
        var redirectURI: String?
    }

    init(
        store: CredentialStore,
        keyAuthentication: @escaping @Sendable (ProviderID) -> any KeyAuthenticating = {
            _ in ZaiKeyLogin()
        },
        authentication: @escaping @Sendable (ProviderID) -> any BrowserAuthenticating = {
            $0 == .codex ? CodexOAuthLogin() as any BrowserAuthenticating : OAuthLogin()
        },
        deviceAuthentication: @escaping @Sendable (ProviderID) -> any DeviceCodeAuthenticating = {
            _ in CopilotDeviceLogin()
        },
        openURL: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) },
        timeoutDuration: Duration = .seconds(300),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.keyAuthentication = keyAuthentication
        self.authentication = authentication
        self.deviceAuthentication = deviceAuthentication
        self.openURL = openURL
        self.timeoutDuration = timeoutDuration
        self.now = now
    }

    /// `.settings` unless a caller says otherwise: that screen has had this
    /// button since before there was anywhere else to put one, and every test
    /// in `LoginControllerTests` models that flow.
    func start(provider: ProviderID, from origin: SignInOrigin = .settings,
               for account: String? = nil) {
        guard !isRunning, Self.providers.contains(provider) else { return }
        message = nil
        successNotice = nil
        // Recorded before anything can go wrong, not after. Every sentence this
        // method can produce is now shown against the row that asked, and the
        // failure below was the one that had none: it set `message` and
        // returned, leaving the note attributed to whichever row asked last —
        // or, on the first press, to no row at all, so the button did nothing
        // visible whatsoever.
        let request = SignInRequest(provider: provider, origin: origin, account: account)
        self.request = request

        if Self.keyProviders.contains(provider) {
            startKey(request)
            return
        }

        if Self.deviceProviders.contains(provider) {
            startDevice(request)
            return
        }

        guard let pair = PKCEPair.generate() else {
            message = Localization.shared("Sign-in did not complete")
            return
        }
        let attempt = Attempt(
            authentication: authentication(provider), pair: pair,
            state: UUID().uuidString, request: request)
        self.attempt = attempt
        isRunning = true
        exchanging = false
        manualCodeExpected = false
        armTimeout(for: attempt.id)
        operation = Task { await openBrowser(for: attempt) }
    }

    /// Waiting for a key, which is all this sign-in does until one arrives.
    ///
    /// No timeout is armed and no request is made. There is nothing in flight
    /// to time out, and a deadline on how long somebody may take to find their
    /// key in another window would be a deadline on them.
    private func startKey(_ request: SignInRequest) {
        keyAttempt = KeyAttempt(request: request)
        keyExpected = true
        isRunning = true
        exchanging = false
        manualCodeExpected = false
    }

    /// The key, as typed. Checked by being used once.
    ///
    /// A refusal leaves the attempt standing. Mistyping a key is the ordinary
    /// way this goes wrong, and ending the attempt would make the correction a
    /// fresh sign-in — the same reason the pasted-code field keeps its attempt
    /// alive when the code does not match.
    func submitKey(_ raw: String) async {
        guard let attempt = keyAttempt, !exchanging, !isSavingAccount else { return }
        exchanging = true
        message = nil
        // The field comes down for as long as the key is being used, which is
        // what lets the screen show that something is happening: while it is up
        // the app is waiting on a person, and a spinner beside it would be
        // claiming otherwise. A refusal puts it back, with the key still in it.
        keyExpected = false

        do {
            let result = try await keyAuthentication(attempt.request.provider).account(for: raw)
            guard keyAttempt?.id == attempt.id, !Task.isCancelled else { return }
            await adopt(result, attempt: attempt.id, origin: attempt.request.origin)
        } catch {
            guard keyAttempt?.id == attempt.id, !Task.isCancelled else { return }
            report(error)
            exchanging = false
            keyExpected = true
        }
    }

    /// The other shape, from the same button.
    ///
    /// No attempt timeout is armed. The grant carries its own deadline and the
    /// loop below honours it; the five minutes every browser attempt gets would
    /// end this one while the code still on screen had ten minutes left, and
    /// the person reading it would have no way to know it had stopped counting.
    private func startDevice(_ request: SignInRequest) {
        let started = DeviceAttempt(request: request)
        deviceAttempt = started
        deviceGrant = nil
        isRunning = true
        exchanging = false
        manualCodeExpected = false
        operation = Task { [weak self] in await self?.runDevice(started) }
    }

    private func runDevice(_ started: DeviceAttempt) async {
        let login = deviceAuthentication(started.request.provider)
        do {
            let grant = try await login.requestCode()
            guard deviceAttempt?.id == started.id, !Task.isCancelled else { return }
            deviceGrant = grant

            // The page is opened for them, and the code stays on our screen to
            // be copied from. A browser that refuses to open is not fatal here
            // the way it is for a redirect flow — the address is on screen and
            // can be typed — so it is said and the attempt goes on waiting.
            if !openURL(grant.verificationURL) {
                message = Localization.shared(
                    "Could not open the browser. Open the page below and enter the code.")
            }

            var interval = grant.interval
            while true {
                try await Task.sleep(for: .seconds(interval))
                guard deviceAttempt?.id == started.id, !Task.isCancelled else { return }
                // Checked before asking rather than after being refused: once
                // the code is stale the service answers the same thing forever,
                // and one more request would only delay saying so.
                guard now() < grant.expiresAt else {
                    throw DeviceCodeRejected(reason: .expired)
                }
                switch try await login.poll(grant) {
                case .pending:
                    continue
                case .slowDown(let next):
                    interval = next
                case .granted(let result):
                    guard deviceAttempt?.id == started.id, !Task.isCancelled else { return }
                    await adopt(result, attempt: started.id, origin: started.request.origin)
                    return
                }
            }
        } catch is CancellationError {
            return
        } catch let rejection as DeviceCodeRejected {
            guard deviceAttempt?.id == started.id else { return }
            switch rejection.reason {
            case .denied:  fail("Sign-in was declined.")
            case .expired: fail("Sign-in timed out")
            }
        } catch {
            guard deviceAttempt?.id == started.id, !Task.isCancelled else { return }
            report(error)
            endAttempt()
        }
    }

    func cancel() {
        // The system keychain write cannot be interrupted or rolled back.
        // Once it starts, report its actual outcome before allowing a retry.
        guard !isSavingAccount else { return }
        endAttempt()
        message = nil
    }

    func dismissSuccessNotice() { successNotice = nil }

    func submit(code raw: String) async {
        guard manualCodeExpected, let attempt, !exchanging else { return }
        switch OAuthCallback.parse(pastedCode: raw, expectedState: attempt.state) {
        case .code(let code): beginExchange(code: code, attempt: attempt)
        case .denied: fail("Sign-in was declined.")
        case .stateMismatch: fail("That reply belongs to a different sign-in. Start again.")
        case .unrelated:
            // An editing mistake can be corrected without spending a new grant.
            message = Localization.shared("That is not the code from the page.")
        }
    }

    private func openBrowser(for started: Attempt) async {
        guard attempt?.id == started.id, !Task.isCancelled else { return }
        let callback = BrowserCallbackListener()
        listener = callback
        let uri: String
        do {
            let port = try await callback.start(port: started.authentication.callbackPort) {
                [weak self] request, connection in
                self?.handle(request: request, on: connection, attemptID: started.id)
            }
            guard attempt?.id == started.id, !Task.isCancelled else {
                callback.stop()
                return
            }
            guard let local = started.authentication.localRedirect(port: port) else {
                throw ProviderFailure(kind: .network, diagnostic: "unusable OAuth callback port")
            }
            uri = local
        } catch {
            guard attempt?.id == started.id, !Task.isCancelled else { return }
            callback.stop()
            listener = nil
            guard let manual = started.authentication.manualRedirectURI else {
                fail("Could not open the Codex sign-in callback. Close any other Codex sign-in and try again.")
                return
            }
            uri = manual
            manualCodeExpected = true
            message = Localization.shared("Copy the code from the page and paste it below")
        }
        attempt?.redirectURI = uri
        let url = started.authentication.authorizationURL(
            redirectURI: uri, pkce: started.pair, state: started.state, manual: manualCodeExpected)
        guard openURL(url) else {
            fail("Could not open the browser. Check your default browser and try again.")
            return
        }
    }

    private func handle(request: String, on connection: NWConnection, attemptID: UUID) {
        guard let attempt, attempt.id == attemptID, !exchanging else {
            connection.cancel()
            return
        }
        let outcome = OAuthCallback.parse(
            requestLine: request, expectedState: attempt.state,
            callbackPath: attempt.authentication.callbackPath)
        switch outcome {
        case .unrelated, .stateMismatch:
            // A stray request must not terminate the genuine browser attempt.
            respond(on: connection, succeeded: false)
        case .denied:
            respond(on: connection, succeeded: false)
            fail("Sign-in was declined.")
        case .code(let code):
            // The browser must not close or claim success before both the
            // exchange and the keychain write have completed.
            pendingBrowserReply = connection
            beginExchange(code: code, attempt: attempt)
        }
    }

    private func beginExchange(code: String, attempt: Attempt) {
        guard self.attempt?.id == attempt.id, !exchanging else { return }
        guard attempt.redirectURI != nil else {
            fail("The sign-in lost its place. Start again.")
            return
        }
        message = nil
        exchanging = true
        manualCodeExpected = false
        listener?.stop()
        listener = nil
        operation = Task { await finish(code: code, attempt: attempt) }
    }

    private func finish(code: String, attempt started: Attempt) async {
        guard let uri = started.redirectURI else { return }
        do {
            let result = try await started.authentication.authenticate(
                code: code, verifier: started.pair.verifier,
                redirectURI: uri, state: started.state)
            guard attempt?.id == started.id, !Task.isCancelled else { return }
            await adopt(result, attempt: started.id, origin: started.request.origin)
            return
        } catch {
            guard attempt?.id == started.id, !Task.isCancelled else { return }
            report(error)
        }
        guard attempt?.id == started.id else { return }
        endAttempt()
    }

    /// Whether the attempt that is reporting back is still the one in hand.
    ///
    /// Either shape may be the one that owns `id`; identifiers are unique, so
    /// asking both is the same question as asking the right one, and asking the
    /// right one would mean every caller knowing which shape it is.
    private func stillCurrent(_ id: UUID) -> Bool {
        attempt?.id == id || deviceAttempt?.id == id || keyAttempt?.id == id
    }

    /// Saving the account, and everything that follows from having saved it.
    ///
    /// Both shapes of sign-in end here. A second copy of this would be a second
    /// place for the success notice, the counter, the browser reply and the
    /// callback to drift apart — and the drift would show up as a sign-in that
    /// worked and a screen that never said so.
    private func adopt(
        _ result: AuthenticatedAccount, attempt id: UUID, origin: SignInOrigin
    ) async {
        do {
            isSavingAccount = true
            timeout?.cancel()
            timeout = nil
            try await store.addLoggedInAccount(result)
            guard stillCurrent(id), !Task.isCancelled else { return }
            message = nil
            successNotice = result.account
            completedSignIns += 1
            finishBrowserReply(succeeded: true)
            endAttempt()
            didAddAccount?(result.account, origin)
        } catch {
            guard stillCurrent(id), !Task.isCancelled else { return }
            report(error)
            endAttempt()
        }
    }

    /// What a failed attempt says, and what it writes down.
    private func report(_ error: any Error) {
        if let failure = error as? ProviderFailure {
            Self.log.error("sign-in failed: \(failure.diagnostic, privacy: .public)")
            Task { await Diagnostics.shared.report(failure, category: "sign-in") }
            message = Localization.shared.failureText(failure.kind)
        } else if error is WouldOverwriteUnreadableAccounts {
            // The sign-in worked; there was nowhere to put it. "Sign-in did
            // not complete" sent people back to the browser to do again,
            // successfully, the one part of this that had not failed — and
            // it would have gone on doing that for as long as the app was
            // installed, because nothing about a second attempt is
            // different from the first.
            Self.log.error("sign-in failed: the account list could not be written")
            Task {
                await Diagnostics.shared.report(
                    .error, category: "sign-in", message: "account list unreadable",
                    failureType: "WouldOverwriteUnreadableAccounts")
            }
            message = Localization.shared(
                "Signed in, but the saved accounts could not be opened to store it.")
        } else {
            let kind = String(describing: type(of: error))
            Self.log.error("sign-in failed: \(kind, privacy: .public)")
            Task {
                await Diagnostics.shared.report(
                    .error, category: "sign-in", message: kind, failureType: kind)
            }
            message = Localization.shared("Sign-in did not complete")
        }
    }

    private func respond(on connection: NWConnection, succeeded: Bool) {
        let response = BrowserSignInPage.response(succeeded: succeeded)
        // Cancelling before this completion discards the browser's response.
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finishBrowserReply(succeeded: Bool) {
        guard let connection = pendingBrowserReply else { return }
        pendingBrowserReply = nil
        respond(on: connection, succeeded: succeeded)
    }

    private func fail(_ key: String) {
        endAttempt()
        message = Localization.shared(key)
    }

    private func armTimeout(for id: UUID) {
        timeout?.cancel()
        let duration = timeoutDuration
        timeout = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self, self.attempt?.id == id else { return }
            self.fail("Sign-in timed out")
        }
    }

    private func endAttempt() {
        // Cancellation, timeout and errors release a waiting browser too, but
        // their page never runs the success-only close script.
        finishBrowserReply(succeeded: false)
        attempt = nil
        deviceAttempt = nil
        deviceGrant = nil
        keyAttempt = nil
        keyExpected = false
        operation?.cancel()
        operation = nil
        listener?.stop()
        listener = nil
        timeout?.cancel()
        timeout = nil
        isRunning = false
        isSavingAccount = false
        manualCodeExpected = false
        exchanging = false
    }
}
