import Foundation
import ProviderKit

/// Public Copilot client configuration.
///
/// The same stance the other two services are read under: the constants belong
/// to the published editor client, they are public by construction, and nothing
/// secret is committed because a public client has no secret. What that costs is
/// written down once in `docs/authentication.md` — these are first-party
/// endpoints, not a versioned integration API, and an upstream change can
/// require an adapter update here.
///
/// There is no authorization-code flow for this client. GitHub requires a client
/// secret at the exchange for that flow and does not accept PKCE in its place,
/// and a desktop application shipping a secret would be shipping it to everyone
/// who downloads it. The device grant needs none, which is why sign-in here has
/// a different shape from the other two.
public enum CopilotEndpoints {
    /// The published editor client. Not a credential: it identifies the
    /// application to the service and is sent in the clear on the first request
    /// of every sign-in.
    public static let clientID = "Iv1.b507a08c87ecfe98"

    public static let deviceCode = URL(string: "https://github.com/login/device/code")!
    public static let token = URL(string: "https://github.com/login/oauth/access_token")!

    /// Who the token belongs to. The numeric identifier is what an account is
    /// filed under, because a login can be changed by its owner and the number
    /// cannot.
    public static let identity = URL(string: "https://api.github.com/user")!

    /// Plan and allowances for the signed-in person. Read-only, and no model is
    /// ever asked for anything — the same promise the Codex usage read makes.
    public static let usage = URL(string: "https://api.github.com/copilot_internal/user")!

    /// The scope asked for at sign-in.
    ///
    /// Reading a name and an allowance needs nothing else. GitHub grants a
    /// public client the scopes the client is registered with rather than
    /// whatever it asks for, so this is a statement of intent more than a
    /// request — which is the reason to keep it at the smallest true thing
    /// rather than at whatever would certainly be enough.
    public static let scope = "read:user"

    /// `Accept` decides the shape of the reply: without it these two endpoints
    /// answer in form encoding, and the error cases — the ones that carry the
    /// whole state machine — come back as a query string.
    public static let jsonHeaders = [
        "Accept": "application/json",
        "Content-Type": "application/x-www-form-urlencoded",
    ]

    /// GitHub's API wants a version and refuses an anonymous caller politely
    /// rather than usefully; the agent is what appears in a rate-limit reply.
    public static func apiHeaders(token: String) -> [String: String] {
        [
            "Authorization": "Bearer \(token)",
            "Accept": "application/json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "Softcap",
        ]
    }

    /// The device grant's own name for itself, spelled by RFC 8628.
    public static let deviceGrantType = "urn:ietf:params:oauth:grant-type:device_code"

    public static func form(_ fields: [String: String]) -> Data {
        FormBody.encode(fields)
    }
}
