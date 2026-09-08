import Testing
import Foundation
@testable import ClaudeProvider

@Suite struct BrowserReturn {

    private static let state = "st-abc-123"

    // MARK: - the listener path

    @Test func readsCodeFromTheRequestLine() {
        let request = "GET /callback?code=abc123&state=\(Self.state) HTTP/1.1\r\nHost: localhost\r\n"
        #expect(OAuthCallback.parse(requestLine: request, expectedState: Self.state)
                == .code("abc123"))
    }

    @Test func toleratesBareNewlines() {
        // Not every client sends CRLF.
        let request = "GET /callback?code=abc&state=\(Self.state) HTTP/1.1\nHost: localhost\n"
        #expect(OAuthCallback.parse(requestLine: request, expectedState: Self.state)
                == .code("abc"))
    }

    @Test func rejectsAForeignState() {
        // A forged redirect would hand us someone else's code.
        let request = "GET /callback?code=abc&state=someone-else HTTP/1.1\r\n"
        #expect(OAuthCallback.parse(requestLine: request, expectedState: Self.state)
                == .stateMismatch)
    }

    @Test func reportsAnExplicitDenial() {
        let request = "GET /callback?error=access_denied&state=\(Self.state) HTTP/1.1\r\n"
        #expect(OAuthCallback.parse(requestLine: request, expectedState: Self.state)
                == .denied(reason: "access_denied"))
    }

    @Test func ignoresAFaviconFetch() {
        // The browser hits the same listener for /favicon.ico.
        let request = "GET /favicon.ico HTTP/1.1\r\nHost: localhost\r\n"
        #expect(OAuthCallback.parse(requestLine: request, expectedState: Self.state) == .unrelated)
    }

    @Test func ignoresGarbage() {
        #expect(OAuthCallback.parse(requestLine: "", expectedState: Self.state) == .unrelated)
        #expect(OAuthCallback.parse(requestLine: "nonsense", expectedState: Self.state) == .unrelated)
    }

    // MARK: - the pasted path

    @Test func splitsCodeFromStateWhenPasted() {
        // The fallback page shows `code#state`; sending it whole always failed.
        #expect(OAuthCallback.parse(pastedCode: "abc123#\(Self.state)", expectedState: Self.state)
                == .code("abc123"))
    }

    @Test func acceptsABareCode() {
        #expect(OAuthCallback.parse(pastedCode: "abc123", expectedState: Self.state)
                == .code("abc123"))
    }

    @Test func trimsWhatThePasteboardAdds() {
        #expect(OAuthCallback.parse(pastedCode: "  abc123#\(Self.state)\n", expectedState: Self.state)
                == .code("abc123"))
    }

    @Test func rejectsAPastedForeignState() {
        #expect(OAuthCallback.parse(pastedCode: "abc#wrong-state", expectedState: Self.state)
                == .stateMismatch)
    }

    @Test func emptyPasteIsNotACode() {
        #expect(OAuthCallback.parse(pastedCode: "   ", expectedState: Self.state) == .unrelated)
        #expect(OAuthCallback.parse(pastedCode: "#\(Self.state)", expectedState: Self.state)
                == .unrelated)
    }
}
