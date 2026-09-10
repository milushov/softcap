import Foundation
import ProviderKit

public struct CodexIdentity: Sendable, Hashable {
    public let accountID: String
    public let displayName: String
    public let planType: String?
}

/// Extracts the identity from `~/.codex/auth.json`.
///
/// The JWT signature is deliberately not verified: the file already sits in the
/// user's home directory, and all we need is a name and a plan to display.
public enum CodexIdentityReader {
    private static let authClaimKey = "https://api.openai.com/auth"

    public static func parse(authJSON: Data) throws -> CodexIdentity {
        guard
            let root = try? JSONSerialization.jsonObject(with: authJSON) as? [String: Any],
            let tokens = root["tokens"] as? [String: Any],
            let idToken = tokens["id_token"] as? String
        else {
            throw ProviderFailure(kind: .malformed, diagnostic: "auth.json has no tokens.id_token")
        }

        return try parse(idToken: idToken, accountID: tokens["account_id"] as? String)
    }

    public static func parse(idToken: String, accountID: String? = nil) throws -> CodexIdentity {
        guard let claims = JWTClaims.decode(idToken) else {
            throw ProviderFailure(kind: .malformed, diagnostic: "id_token not parsed")
        }

        let auth = claims[authClaimKey] as? [String: Any] ?? [:]
        guard let accountID = accountID ?? auth["chatgpt_account_id"] as? String,
              !accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderFailure(kind: .malformed, diagnostic: "codex identity has no account id")
        }
        let name = claims["name"] as? String
        let email = claims["email"] as? String

        return CodexIdentity(
            accountID: accountID,
            displayName: name ?? email ?? accountID,
            planType: auth["chatgpt_plan_type"] as? String
        )
    }

}
