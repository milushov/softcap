import Foundation
import AppKit
import OSLog
import Network
import ProviderKit
import ClaudeProvider
import Credentials
import StatusUI

/// Runs the browser sign-in: opens a listener on a free port, opens the sign-in
/// page and waits for the return with a code.
@MainActor
final class LoginController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var message: String?
    /// Set when the localhost return did not work and the code must be pasted.
    @Published private(set) var manualCodeExpected = false
    /// Counts completed sign-ins. A counter rather than a flag because two
    /// sign-ins in a row must be two events, and `message` cannot serve: it
    /// changes on failure too, and refreshing after a failed sign-in would poll
    /// for an account that was never added.
    @Published private(set) var completedSignIns = 0

    private let login = OAuthLogin()
    /// `ProviderFailure.diagnostic` is written for a log and shown to nobody —
    /// but nothing was writing it down, so three different failures arrived in
    /// the interface as one sentence and left no way to tell them apart.
    private static let log = Logger(subsystem: "app.softcap.Softcap", category: "login")
    private let store: CredentialStore
    private var listener: NWListener?
    private var pkce: PKCEPair?
    private var expectedState: String?
    private var redirectURI: String?
    private var timeout: Task<Void, Never>?

    init(store: CredentialStore) { self.store = store }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        message = nil
        manualCodeExpected = false

        guard let pair = PKCEPair.generate() else {
            // The system supplied no random bytes — signing in without them is
            // not safe.
            message = Localization.shared("Sign-in did not complete")
            isRunning = false
            return
        }
        let state = UUID().uuidString
        pkce = pair
        expectedState = state

        Task { await openBrowser(pair: pair, state: state) }
    }

    /// Binds the port first and opens the browser only once it is listening: the
    /// address has to be real before it is handed to the service.
    private func openBrowser(pair: PKCEPair, state: String) async {
        guard let port = try? await startListener(),
              let uri = OAuthEndpoints.localRedirect(port: port)
        else {
            // The port could not be bound — fall back to pasting the code.
            fallBackToManual(pair: pair, state: state)
            return
        }
        redirectURI = uri
        NSWorkspace.shared.open(
            login.authorizationURL(redirectURI: uri, pkce: pair, state: state, manual: false)
        )
        armTimeout()
    }

    /// The manual path: the code copied from the page and pasted into the field.
    /// Parsing lives in `OAuthCallback`, where it is covered by tests.
    func submit(code raw: String) async {
        guard let pair = pkce, let uri = redirectURI, let state = expectedState else { return }

        switch OAuthCallback.parse(pastedCode: raw, expectedState: state) {
        case .code(let code):
            await finish(code: code, verifier: pair.verifier, redirectURI: uri, state: state)
        // One message for these three said the app could not read something. It
        // read all three perfectly: one is the person declining, one is a reply
        // belonging to another attempt, and one — much the most likely when
        // pasting by hand — is text that is not a code at all.
        case .denied:
            message = Localization.shared("Sign-in was declined.")
            isRunning = false
            manualCodeExpected = false
        case .stateMismatch:
            message = Localization.shared(
                "That reply belongs to a different sign-in. Start again."
            )
            isRunning = false
            manualCodeExpected = false
        case .unrelated:
            message = Localization.shared("That is not the code from the page.")
            isRunning = false
            manualCodeExpected = false
        }
    }

    func cancel() {
        stopListener()
        isRunning = false
        manualCodeExpected = false
        message = nil
    }

    // MARK: - internals

    private func startListener() async throws -> UInt16 {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
                data, _, _, _ in
                guard let data, let request = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in self?.handle(request: request, on: connection) }
            }
        }

        // Readiness is what has to be waited for, not the port appearing.
        // `NWListener.port` answers with the endpoint it was *asked* for until
        // it is actually listening, and `.any` answers as zero — so waiting for
        // the port to become non-nil returns at once, with a port that is not
        // bound to anything. That zero then travelled to the browser.
        do {
            return try await withCheckedThrowingContinuation { continuation in
                let once = ResumeOnce()
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        guard let port = listener.port?.rawValue, port != 0 else {
                            guard once.claim() else { return }
                            continuation.resume(throwing: ProviderFailure(
                                kind: .network, diagnostic: "listener ready on port 0"))
                            return
                        }
                        guard once.claim() else { return }
                        continuation.resume(returning: port)
                    case .failed(let error):
                        guard once.claim() else { return }
                        continuation.resume(throwing: ProviderFailure(
                            kind: .network, diagnostic: "listener failed: \(error)"))
                    case .cancelled:
                        guard once.claim() else { return }
                        continuation.resume(throwing: ProviderFailure(
                            kind: .network, diagnostic: "listener cancelled"))
                    default:
                        break
                    }
                }
                listener.start(queue: .main)
            }
        } catch {
            // The listener may already be running: without stopping it the
            // socket and its handler would live on for the rest of the process.
            stopListener()
            throw error
        }
    }

    private func handle(request: String, on connection: NWConnection) {
        defer { connection.cancel() }
        guard let state = expectedState else { return }

        let outcome = OAuthCallback.parse(requestLine: request, expectedState: state)

        // A browser fetching /favicon.ico reaches this listener too. Answering
        // it as a failure would abort a sign-in that is still in progress.
        if case .unrelated = outcome {
            respond(on: connection, ok: false)
            return
        }

        // `.unrelated` is already gone above, so this is a decline or a reply
        // that does not match the request we sent — different enough that one
        // sentence for both told nobody anything.
        guard case .code(let code) = outcome else {
            respond(on: connection, ok: false)
            if case .denied = outcome {
                message = Localization.shared("Sign-in was declined.")
            } else {
                message = Localization.shared(
                    "That reply belongs to a different sign-in. Start again."
                )
            }
            isRunning = false
            stopListener()
            return
        }

        respond(on: connection, ok: true)
        // Not a browser problem at all: the app has lost the verifier it started
        // with, so there is nothing to exchange the code against. Blaming the
        // reply sent the reader looking in the wrong place.
        guard let pair = pkce, let uri = redirectURI else {
            message = Localization.shared("The sign-in lost its place. Start again.")
            isRunning = false
            stopListener()
            return
        }

        stopListener()
        Task { await finish(code: code, verifier: pair.verifier, redirectURI: uri, state: state) }
    }

    private func respond(on connection: NWConnection, ok: Bool) {
        let text = ok
            ? Localization.shared("Done. You can return to the app.")
            : Localization.shared("Something went wrong.")
        let body = "<html><meta charset=\"utf-8\"><body style=\"font-family:-apple-system;padding:40px\">\(text)</body></html>"
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in })
    }

    private func finish(
        code: String, verifier: String, redirectURI: String, state: String
    ) async {
        do {
            let tokens = try await login.exchange(
                code: code, verifier: verifier, redirectURI: redirectURI, state: state
            )
            guard let refresh = tokens.refreshToken else {
                throw ProviderFailure(kind: .needsLogin, diagnostic: "no refresh token returned")
            }

            let headers = [
                "Authorization": "Bearer \(tokens.accessToken)",
                "anthropic-beta": "oauth-2025-04-20",
                "User-Agent": OAuthEndpoints.userAgent,
            ]
            let url = URL(string: "https://api.anthropic.com/api/oauth/profile")!
            let (data, status) = try await URLSessionHTTPClient().get(url, headers: headers)
            guard status == 200, let profile = try? ClaudeProfileResponse.parse(data) else {
                throw ProviderFailure(kind: .needsLogin, diagnostic: "profile read failed")
            }

            try await store.addLoggedInAccount(
                uuid: profile.uuid, displayName: profile.displayName, refreshToken: refresh
            )
            message = String(format: Localization.shared("Account %@ added"), profile.displayName)
            completedSignIns += 1
        } catch let failure as ProviderFailure {
            Self.log.error("sign-in failed: \(failure.diagnostic, privacy: .public)")
            message = Localization.shared.failureText(failure.kind)
        } catch {
            Self.log.error("sign-in failed: \(String(describing: error), privacy: .public)")
            message = Localization.shared("Sign-in did not complete")
        }
        isRunning = false
        manualCodeExpected = false
        timeout?.cancel()
    }

    private func fallBackToManual(pair: PKCEPair, state: String) {
        redirectURI = OAuthEndpoints.manualRedirect
        manualCodeExpected = true
        message = Localization.shared("Copy the code from the page and paste it below")
        // Otherwise an abandoned sign-in leaves the "Add account" button
        // disabled forever: `isRunning` is never cleared.
        armTimeout()
        NSWorkspace.shared.open(login.authorizationURL(
            redirectURI: OAuthEndpoints.manualRedirect, pkce: pair, state: state, manual: true
        ))
    }

    /// The listener must not linger if the person closed the tab. Five minutes,
    /// not two: signing in to a second subscription means a password, a
    /// verification code and a consent screen, and the earlier limit could
    /// expire while the browser was still on the first of them.
    private func armTimeout() {
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(300))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.isRunning else { return }
                self.stopListener()
                self.isRunning = false
                self.message = Localization.shared("Sign-in timed out")
            }
        }
    }

    private func stopListener() {
        // The handler holds the continuation's guard; clearing it first keeps
        // the cancellation below from being reported as a sign-in failure.
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        listener = nil
        timeout?.cancel()
    }
}

/// `NWListener` reports its state through a `@Sendable` handler, which cannot
/// write to a local variable — and a continuation must be resumed exactly once,
/// while `.ready` may be followed by `.cancelled`.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
