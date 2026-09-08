import Foundation

/// Sign-in endpoints, taken from the constants of the installed Claude Code.
///
/// Claude Code carries **two** authorize URLs and they lead to different places:
///
/// - `CONSOLE_AUTHORIZE_URL` — `platform.claude.com/oauth/authorize`, the API
///   console: keys, usage and billing for the developer API.
/// - `CLAUDE_AI_AUTHORIZE_URL` — `claude.com/cai/oauth/authorize`, the
///   subscription sign-in, which redirects on to `claude.ai/oauth/authorize`.
///
/// This app watches **subscription** limits, so the second one is correct. The
/// first was used at first and sent people to "How will you use the Claude API?"
/// — a page for creating an API account, which is not what anyone asked for.
public enum OAuthEndpoints {
    public static let authorize = URL(string: "https://claude.com/cai/oauth/authorize")!
    public static let token = URL(string: "https://platform.claude.com/v1/oauth/token")!
    public static let manualRedirect = "https://platform.claude.com/oauth/code/callback"
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    /// The scopes a real subscription token carries, read from the keychain item
    /// Claude Code writes. The console scope `org:create_api_key` is deliberately
    /// absent: this app never creates API keys, and asking for a permission it
    /// does not need would be wrong on its own.
    public static let scope =
        "user:inference user:profile user:sessions:claude_code user:mcp_servers user:file_upload"

    /// The client this app presents itself as.
    ///
    /// Not decoration: without it the token endpoint answers `403` with
    /// Cloudflare's `error code: 1010`, a block on the caller's fingerprint
    /// rather than an OAuth reply — and the app read that as "sign-in
    /// required". Sent with the same header the sign-in was started under, so
    /// exchange and refresh are the same caller as the profile read.
    public static let userAgent = "claude-cli/2.0.0 (external, cli)"

    /// The headers every OAuth call carries. One definition, because the header
    /// was present on two of the four calls and missing on the two that
    /// mattered.
    public static let jsonHeaders = [
        "Content-Type": "application/json",
        "User-Agent": userAgent,
    ]

    /// The local return address, or `nil` when the port is unusable.
    ///
    /// Zero is what a socket is asked for when any free port will do, and it is
    /// also what `NWListener` reports back until it is actually listening. Sent
    /// to the service it comes back as "Redirect URI http://localhost:0/callback
    /// is not supported by client" — so the check lives here, where a test can
    /// hold it, rather than in the caller that happened to get it wrong.
    public static func localRedirect(port: UInt16) -> String? {
        guard port != 0 else { return nil }
        return "http://localhost:\(port)/callback"
    }
}
