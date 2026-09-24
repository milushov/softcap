import Foundation
import ProviderKit
import CopilotProvider

/// Rotating a device grant, for the case where the service issues one to rotate.
///
/// Usually it does not: a public client's token has no expiry and no refresh
/// token, and `ProviderID.rotatesCredentials` is what tells the store to serve
/// it as it is. But the client can be configured to expire tokens, and when it
/// is, the sign-in reply carries a refresh token like any other. This exists so
/// that case follows the ordinary path instead of arriving at a store with
/// nowhere to send it — which is how it was found: a grant that did rotate
/// failed with "provider has no token refresher", a sentence no reader could
/// have acted on.
public struct GitHubTokenRefresher: TokenRefreshing {
    private let http: any HTTPClient

    public init(http: any HTTPClient = URLSessionHTTPClient()) { self.http = http }

    public func refresh(refreshToken: String) async throws -> RefreshedTokens {
        let (data, status) = try await http.post(
            CopilotEndpoints.token, headers: CopilotEndpoints.jsonHeaders,
            body: CopilotEndpoints.form([
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": CopilotEndpoints.clientID,
            ]))

        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        // This endpoint answers 200 and puts the refusal in the body, the same
        // way the device poll does, so the status cannot be read on its own.
        if let error = root?["error"] as? String {
            // The spec's word for a token the server has finished with. Asking
            // again with it gets the same answer forever, so the caller is told
            // to stop keeping it rather than to try later.
            if ["bad_refresh_token", "invalid_grant", "expired_token"].contains(error) {
                throw RefreshRejected()
            }
            throw ProviderFailure(kind: .needsLogin, diagnostic: "copilot refresh refused: \(error)")
        }

        guard status == 200, let access = root?["access_token"] as? String, !access.isEmpty else {
            throw ProviderFailure(
                kind: .network, diagnostic: "copilot refresh failed, HTTP \(status)")
        }

        return RefreshedTokens(
            accessToken: access,
            refreshToken: root?["refresh_token"] as? String,
            expiresIn: (root?["expires_in"] as? NSNumber)?.doubleValue)
    }
}
