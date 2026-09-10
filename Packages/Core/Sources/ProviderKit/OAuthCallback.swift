import Foundation

/// Reading what comes back from the browser.
///
/// Lives here rather than in the app because this is where mistakes hide: the
/// manual path silently sent `code#state` as the code and every exchange failed,
/// and nothing could have caught it — the parsing sat in a view controller with
/// a live listener attached. Pure functions can be tested.
public enum OAuthCallback {

    /// What a browser return yields.
    public enum Outcome: Sendable, Equatable {
        /// A code, already checked against the expected state.
        case code(String)
        /// The user declined, or the server refused. Carries the raw reason for
        /// the log; the interface speaks from `ProviderFailure.Kind`.
        case denied(reason: String)
        /// The request reached the listener but is not a sign-in return at all —
        /// a favicon fetch, a stray probe.
        case unrelated
        /// A return whose state does not match: a forged redirect, and its code
        /// must never be exchanged.
        case stateMismatch
    }

    /// Parses the first line of an HTTP request the local listener received.
    ///
    /// Expects `GET /callback?code=…&state=… HTTP/1.1`.
    public static func parse(
        requestLine request: String, expectedState: String, callbackPath: String = "/callback"
    ) -> Outcome {
        guard let line = request.split(separator: "\r\n").first ?? request.split(separator: "\n").first,
              line.split(separator: " ").first == "GET",
              let path = line.split(separator: " ").dropFirst().first,
              path.hasPrefix("/"), !path.hasPrefix("//"),
              let components = URLComponents(string: "http://localhost\(path)"),
              components.path == callbackPath
        else { return .unrelated }

        let items = components.queryItems ?? []
        // A browser fetching /favicon.ico reaches the same listener.
        guard !items.isEmpty else { return .unrelated }

        guard items.contains(where: { $0.name == "code" || $0.name == "error" }) else {
            return .unrelated
        }
        guard items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == expectedState else {
            return .stateMismatch
        }
        if let error = items.first(where: { $0.name == "error" })?.value {
            return .denied(reason: error)
        }
        guard items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            return .unrelated
        }
        return .code(code)
    }

    /// Parses a code pasted by hand from the fallback page.
    ///
    /// That page shows `code#state`, not a bare code. Sending the whole string
    /// for exchange fails every time — which is exactly what happened before
    /// this function existed.
    public static func parse(pastedCode raw: String, expectedState: String) -> Outcome {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unrelated }

        let parts = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let code = String(parts[0])
        guard !code.isEmpty else { return .unrelated }

        // A pasted value may legitimately carry no state — some pages show the
        // code alone. Only a state that is present and wrong is a mismatch.
        if parts.count > 1, !parts[1].isEmpty, String(parts[1]) != expectedState {
            return .stateMismatch
        }
        return .code(code)
    }
}
