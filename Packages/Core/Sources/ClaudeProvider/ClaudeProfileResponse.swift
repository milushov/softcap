import Foundation
import ProviderKit

public struct ClaudeProfile: Sendable, Hashable {
    public let uuid: String
    public let displayName: String
    public let planLabel: String
}

public enum ClaudeProfileResponse {

    private struct Body: Decodable {
        let account: Account?
        let organization: Organization?

        struct Account: Decodable {
            let uuid: String?
            let displayName: String?
            let email: String?
            enum CodingKeys: String, CodingKey {
                case uuid, displayName = "display_name", email
            }
        }

        struct Organization: Decodable {
            let rateLimitTier: String?
            enum CodingKeys: String, CodingKey { case rateLimitTier = "rate_limit_tier" }
        }
    }

    public static func parse(_ data: Data) throws -> ClaudeProfile {
        guard let body = try? JSONDecoder().decode(Body.self, from: data),
              let uuid = body.account?.uuid
        else {
            throw ProviderFailure(kind: .malformed, diagnostic: "profile not parsed")
        }

        return ClaudeProfile(
            uuid: uuid,
            displayName: body.account?.email ?? body.account?.displayName ?? uuid,
            planLabel: planLabel(for: body.organization?.rateLimitTier)
        )
    }

    private static func planLabel(for tier: String?) -> String {
        switch tier {
        case "default_claude_max_20x": "Max 20x"
        case "default_claude_max_5x":  "Max 5x"
        case "default_claude_pro":     "Pro"
        case let other?:               other
        case nil:                      "—"
        }
    }
}
