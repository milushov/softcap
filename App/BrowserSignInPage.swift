import Foundation
import StatusUI

/// A final browser response, sent only when the outcome is known. App activation
/// is native; blocking JavaScript or refusing window.close() cannot prevent it.
@MainActor
enum BrowserSignInPage {
    static func response(succeeded: Bool) -> String {
        let loc = Localization.shared
        let title = loc(succeeded ? "Signed in successfully" : "Sign-in did not complete")
        let detail = loc(succeeded
            ? "Your account is connected. You can close this tab."
            : "Return to Softcap to try signing in again.")
        let close = succeeded ? "try { window.close(); } catch {}" : ""
        let body = """
        <!doctype html>
        <html dir="auto"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(title)) · Softcap</title>
        <style>
        :root { color-scheme: light dark; }
        body { font: 16px/1.5 -apple-system, BlinkMacSystemFont, sans-serif;
               max-width: 32em; margin: 12vh auto; padding: 24px; }
        h1 { font-size: 24px; } p { opacity: .75; }
        </style></head><body>
        <h1>\(escape(title))</h1><p>\(escape(detail))</p>
        <script>
        try { window.history.replaceState(null, "", window.location.pathname); } catch {}
        \(close)
        </script></body></html>
        """
        let status = succeeded ? "200 OK" : "400 Bad Request"
        return "HTTP/1.1 \(status)\r\n"
            + "Content-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(body.utf8.count)\r\n"
            + "Cache-Control: no-store\r\nReferrer-Policy: no-referrer\r\n"
            + "Connection: close\r\n\r\n\(body)"
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
