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

        let parts = idToken.split(separator: ".")
        guard parts.count >= 2, let body = decodeSegment(String(parts[1])),
              let claims = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            throw ProviderFailure(kind: .malformed, diagnostic: "id_token not parsed")
        }

        let auth = claims[authClaimKey] as? [String: Any] ?? [:]
        let accountID = auth["chatgpt_account_id"] as? String ?? "unknown"
        let name = claims["name"] as? String
        let email = claims["email"] as? String

        return CodexIdentity(
            accountID: accountID,
            displayName: name ?? email ?? accountID,
            planType: auth["chatgpt_plan_type"] as? String
        )
    }

    private static func decodeSegment(_ segment: String) -> Data? {
        var s = segment.replacingOccurrences(of: "-", with: "+")
                       .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }
}
