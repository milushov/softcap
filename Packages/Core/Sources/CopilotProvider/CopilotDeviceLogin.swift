import Foundation
import ProviderKit

/// Signing in by carrying a code to the service.
///
/// The person is shown a short string and a page; this asks the service, every
/// few seconds, whether they have typed it yet. Nothing listens on a port and
/// no reply is caught, so the two failure modes the loopback flow has — a busy
/// port and a browser that will not close its own tab — do not exist here. The
/// ones that replace them are a code the person never gets to, and a code they
/// deliberately refuse.
public struct CopilotDeviceLogin: DeviceCodeAuthenticating {
    public let provider: ProviderID = .copilot

    private let http: any HTTPClient
    private let now: @Sendable () -> Date

    public init(
        http: any HTTPClient = URLSessionHTTPClient(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.http = http
        self.now = now
    }

    public func requestCode() async throws -> DeviceCodeGrant {
        let (data, code) = try await http.post(
            CopilotEndpoints.deviceCode,
            headers: CopilotEndpoints.jsonHeaders,
            body: CopilotEndpoints.form([
                "client_id": CopilotEndpoints.clientID,
                "scope": CopilotEndpoints.scope,
            ])
        )

        guard code == 200, let root = Self.object(data) else {
            throw ProviderFailure(
                kind: code == 200 ? .malformed : .network,
                diagnostic: "device code request came back HTTP \(code)")
        }

        guard let device = root["device_code"] as? String, !device.isEmpty,
              let user = root["user_code"] as? String, !user.isEmpty,
              let page = (root["verification_uri"] as? String).flatMap(URL.init(string:))
        else {
            throw ProviderFailure(kind: .malformed, diagnostic: "device code reply is incomplete")
        }

        // Both have defaults in RFC 8628, and a reply that omits them is not
        // malformed. Five seconds is the spec's own floor; fifteen minutes is
        // what this service grants and a sane bound on a screen nobody is
        // watching.
        let interval = (root["interval"] as? NSNumber)?.doubleValue ?? 5
        let lifetime = (root["expires_in"] as? NSNumber)?.doubleValue ?? 900

        return DeviceCodeGrant(
            deviceCode: device, userCode: user, verificationURL: page,
            interval: max(interval, 1), expiresAt: now().addingTimeInterval(lifetime))
    }

    public func poll(_ grant: DeviceCodeGrant) async throws -> DeviceCodePoll {
        let (data, code) = try await http.post(
            CopilotEndpoints.token,
            headers: CopilotEndpoints.jsonHeaders,
            body: CopilotEndpoints.form([
                "client_id": CopilotEndpoints.clientID,
                "device_code": grant.deviceCode,
                "grant_type": CopilotEndpoints.deviceGrantType,
            ])
        )

        // The whole state machine arrives with a 200 and an `error` field, so
        // the status alone decides nothing. A non-200 here is the network or the
        // service, not the person.
        guard let root = Self.object(data) else {
            throw ProviderFailure(
                kind: code == 200 ? .malformed : .network,
                diagnostic: "device token reply came back HTTP \(code)")
        }

        if let access = root["access_token"] as? String, !access.isEmpty {
            let account = try await identify(token: access)
            return .granted(AuthenticatedAccount(
                account: account,
                tokens: RefreshedTokens(
                    accessToken: access,
                    // Present only when the client is configured to expire
                    // tokens. Absent is the ordinary case and is not an error:
                    // `ProviderID.rotatesCredentials` is what tells the store
                    // that, for this service, absent means static rather than
                    // spent.
                    refreshToken: root["refresh_token"] as? String,
                    expiresIn: (root["expires_in"] as? NSNumber)?.doubleValue
                )
            ))
        }

        switch root["error"] as? String {
        case "authorization_pending":
            return .pending
        case "slow_down":
            // The service raises the interval rather than restating it, and an
            // attempt that kept the granted one would be told off again.
            return .slowDown(max((root["interval"] as? NSNumber)?.doubleValue ?? grant.interval + 5, 1))
        case "expired_token":
            throw DeviceCodeRejected(reason: .expired)
        case "access_denied":
            throw DeviceCodeRejected(reason: .denied)
        case let other:
            throw ProviderFailure(
                kind: .needsLogin,
                diagnostic: "device sign-in refused: \(other ?? "no reason given")")
        }
    }

    /// Who the token belongs to.
    ///
    /// Filed under the numeric identifier because a login can be changed by the
    /// person who owns it, and an account that renamed itself would otherwise
    /// arrive as a second account beside the first. The login is what the row
    /// shows, which is the pair every provider here keeps: a stable handle and
    /// a name somebody recognises.
    private func identify(token: String) async throws -> AccountRef {
        let (data, code) = try await http.get(
            CopilotEndpoints.identity, headers: CopilotEndpoints.apiHeaders(token: token))

        guard code == 200, let root = Self.object(data) else {
            throw ProviderFailure(
                kind: code == 401 || code == 403 ? .needsLogin : .network,
                diagnostic: "identity read came back HTTP \(code)")
        }

        guard let number = root["id"] as? NSNumber else {
            throw ProviderFailure(kind: .malformed, diagnostic: "identity reply has no id")
        }
        let handle = number.stringValue
        let login = (root["login"] as? String) ?? handle

        return AccountRef(
            id: "copilot/\(handle)", provider: .copilot, handle: handle, lastKnownName: login)
    }

    private static func object(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
