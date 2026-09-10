import Testing
import ProviderKit

@Suite struct CallbackIsolation {
    @Test func codexRequiresItsOwnCallbackPath() {
        let suffix = "?code=reply&state=attempt HTTP/1.1\r\n"
        #expect(OAuthCallback.parse(requestLine: "GET /auth/callback" + suffix,
            expectedState: "attempt", callbackPath: "/auth/callback") == .code("reply"))
        for path in ["/callback", "/favicon.ico", "/", "/auth/callback/extra"] {
            #expect(OAuthCallback.parse(requestLine: "GET " + path + suffix,
                expectedState: "attempt", callbackPath: "/auth/callback") == .unrelated)
        }
    }

    @Test func errorsAlsoRequireTheAttemptState() {
        #expect(OAuthCallback.parse(requestLine: "GET /callback?error=denied&state=other HTTP/1.1\r\n",
            expectedState: "attempt") == .stateMismatch)
        #expect(OAuthCallback.parse(requestLine: "GET /callback?error=denied HTTP/1.1\r\n",
            expectedState: "attempt") == .stateMismatch)
    }

    @Test func rejectsDuplicateParametersAndUnexpectedMethods() {
        #expect(OAuthCallback.parse(requestLine: "GET /callback?code=a&state=attempt&state=other HTTP/1.1\r\n",
            expectedState: "attempt") == .stateMismatch)
        #expect(OAuthCallback.parse(requestLine: "GET /callback?code=a&code=b&state=attempt HTTP/1.1\r\n",
            expectedState: "attempt") == .unrelated)
        #expect(OAuthCallback.parse(requestLine: "POST /callback?code=a&state=attempt HTTP/1.1\r\n",
            expectedState: "attempt") == .unrelated)
    }
}
