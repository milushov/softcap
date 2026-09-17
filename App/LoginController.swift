import Foundation
import AppKit
import OSLog
import Network
import ProviderKit
import ClaudeProvider
import CodexProvider
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
    static let providers: [ProviderID] = [.claude, .codex]
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
    @Published private(set) var completedSignIns = 0
    @Published private(set) var successNotice: AccountRef?

    /// The origin travels with the account because the attempt is torn down
    /// before this is called — `finish` ends it, and then reports. A handler
    /// reading `request` here would read `nil` every time.
    var didAddAccount: (@MainActor (AccountRef, SignInOrigin) -> Void)?

    private static let log = Logger(subsystem: "app.softcap.Softcap", category: "login")
    private let store: CredentialStore
    private let authentication: @Sendable (ProviderID) -> any BrowserAuthenticating
    private let openURL: @MainActor (URL) -> Bool
    private let timeoutDuration: Duration
    private var listener: BrowserCallbackListener?
    private var operation: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var attempt: Attempt?
    private var exchanging = false
    private var pendingBrowserReply: NWConnection?

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
        authentication: @escaping @Sendable (ProviderID) -> any BrowserAuthenticating = {
            $0 == .codex ? CodexOAuthLogin() as any BrowserAuthenticating : OAuthLogin()
        },
        openURL: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) },
        timeoutDuration: Duration = .seconds(300)
    ) {
        self.store = store
        self.authentication = authentication
        self.openURL = openURL
        self.timeoutDuration = timeoutDuration
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
            isSavingAccount = true
            timeout?.cancel()
            timeout = nil
            try await store.addLoggedInAccount(result)
            guard attempt?.id == started.id, !Task.isCancelled else { return }
            message = nil
            successNotice = result.account
            completedSignIns += 1
            finishBrowserReply(succeeded: true)
            let origin = started.request.origin
            endAttempt()
            didAddAccount?(result.account, origin)
            return
        } catch {
            guard attempt?.id == started.id, !Task.isCancelled else { return }
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
        guard attempt?.id == started.id else { return }
        endAttempt()
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
