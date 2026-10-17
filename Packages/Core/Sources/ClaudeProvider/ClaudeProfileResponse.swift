import Foundation
import ProviderKit

public struct ClaudeProfile: Sendable, Hashable {
    public let uuid: String
    public let displayName: String
    public let planLabel: String
    /// The account answers but pays for nothing: the subscription ran out or
    /// was cancelled. The usage endpoint then refuses it with a 429, which
    /// on its own reads exactly like a rate limit.
    public let subscriptionLapsed: Bool

    public init(uuid: String, displayName: String, planLabel: String, subscriptionLapsed: Bool = false) {
        self.uuid = uuid
        self.displayName = displayName
        self.planLabel = planLabel
        self.subscriptionLapsed = subscriptionLapsed
    }
}

public enum ClaudeProfileResponse {

    private struct Body: Decodable {
        let account: Account?
        let organization: Organization?

        struct Account: Decodable {
            let uuid: String?
            let displayName: String?
            let email: String?
            let hasClaudeMax: Bool?
            let hasClaudePro: Bool?
            enum CodingKeys: String, CodingKey {
                case uuid, displayName = "display_name", email
                case hasClaudeMax = "has_claude_max", hasClaudePro = "has_claude_pro"
            }
        }

        struct Organization: Decodable {
            let rateLimitTier: String?
            let organizationType: String?
            let seatTier: String?
            let subscriptionStatus: String?
            enum CodingKeys: String, CodingKey {
                case rateLimitTier = "rate_limit_tier"
                case organizationType = "organization_type"
                case seatTier = "seat_tier"
                case subscriptionStatus = "subscription_status"
            }
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
            planLabel: planLabel(for: body.organization?.rateLimitTier),
            subscriptionLapsed: lapsed(body)
        )
    }

    /// Statuses under which the plan still works. `past_due` is a card that
    /// failed and is being retried; the service keeps the plan meanwhile.
    private static let payingStatuses: Set<String> = ["active", "trialing", "past_due"]

    /// Only what the profile says outright. A field that is missing proves
    /// nothing, and a team or enterprise seat is paid for by someone else:
    /// its personal flags are false on an account that works.
    private static func lapsed(_ body: Body) -> Bool {
        if let status = body.organization?.subscriptionStatus {
            return !payingStatuses.contains(status)
        }
        let type = body.organization?.organizationType ?? ""
        let seated = body.organization?.seatTier != nil
            || type.contains("team") || type.contains("enterprise")
        return !seated
            && body.account?.hasClaudeMax == false
            && body.account?.hasClaudePro == false
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
