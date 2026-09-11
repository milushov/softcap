import Testing
import Foundation
import JavaScriptCore

@Suite @MainActor struct BrowserSignInPageTests {
    @Test(arguments: [false, true])
    func pageClosesOnlyOnSuccessAndRemovesCallbackQuery(succeeded: Bool) throws {
        let response = BrowserSignInPage.response(succeeded: succeeded)
        let parts = response.components(separatedBy: "\r\n\r\n")
        #expect(parts.count == 2)
        let body = try #require(parts.last)
        let headers = try #require(parts.first)
        #expect(headers.contains("Content-Length: \(body.utf8.count)\r\n"))
        #expect(headers.contains("Cache-Control: no-store"))
        #expect(headers.contains("Referrer-Policy: no-referrer"))
        let context = try #require(JSContext())
        context.evaluateScript("""
        var closes = 0;
        var rewritten = null;
        var window = {
            location: { pathname: "/auth/callback", search: "?code=reply&state=example" },
            history: { replaceState: function(state, title, url) { rewritten = url; } },
            close: function() { closes += 1; }
        };
        """)
        context.evaluateScript(try script(in: body))
        #expect(context.exception == nil)
        #expect(context.objectForKeyedSubscript("closes")?.toInt32() == (succeeded ? 1 : 0))
        #expect(context.objectForKeyedSubscript("rewritten")?.toString() == "/auth/callback")
    }

    @Test func blockedBrowserAPIsDoNotBreakTheFallbackPage() throws {
        let response = BrowserSignInPage.response(succeeded: true)
        let context = try #require(JSContext())
        context.evaluateScript("""
        var closes = 0;
        var window = {
            location: { pathname: "/callback" },
            history: { replaceState: function() { throw new Error("blocked"); } },
            close: function() { closes += 1; throw new Error("blocked"); }
        };
        """)
        context.evaluateScript(try script(in: response))
        #expect(context.exception == nil)
        #expect(context.objectForKeyedSubscript("closes")?.toInt32() == 1)
        #expect(response.contains("<h1>"))
        #expect(response.contains("<p>"))
    }

    private func script(in page: String) throws -> String {
        let start = try #require(page.range(of: "<script>"))
        let end = try #require(page.range(of: "</script>"))
        return String(page[start.upperBound..<end.lowerBound])
    }
}
