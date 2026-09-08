import Testing
import Foundation
import ProviderKit
@testable import ClaudeProvider

private func data(_ s: String) -> Data { s.data(using: .utf8)! }

@Test func readsIdentityAndPlan() throws {
    let body = """
    {"account":{"uuid":"a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d","display_name":"Alex",
      "email":"alex@example.com","has_claude_max":true},
     "organization":{"uuid":"8033be31","name":"org","rate_limit_tier":"default_claude_max_20x"}}
    """
    let profile = try ClaudeProfileResponse.parse(data(body))
    #expect(profile.uuid == "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d")
    #expect(profile.displayName == "alex@example.com")
    #expect(profile.planLabel == "Max 20x")
}

@Test func mapsKnownTiersToShortLabels() throws {
    func label(_ tier: String) throws -> String {
        let body = """
        {"account":{"uuid":"u","email":"e@x.y"},"organization":{"rate_limit_tier":"\(tier)"}}
        """
        return try ClaudeProfileResponse.parse(data(body)).planLabel
    }
    #expect(try label("default_claude_max_20x") == "Max 20x")
    #expect(try label("default_claude_max_5x") == "Max 5x")
    #expect(try label("default_claude_pro") == "Pro")
}

@Test func keepsUnknownTierVerbatim() throws {
    let body = """
    {"account":{"uuid":"u","email":"e@x.y"},"organization":{"rate_limit_tier":"nova_plan"}}
    """
    #expect(try ClaudeProfileResponse.parse(data(body)).planLabel == "nova_plan")
}

@Test func fallsBackToDisplayNameWhenEmailMissing() throws {
    let body = """
    {"account":{"uuid":"u","display_name":"Иван"},"organization":{"rate_limit_tier":"default_claude_pro"}}
    """
    #expect(try ClaudeProfileResponse.parse(data(body)).displayName == "Иван")
}

@Test func failsWithoutAccountUUID() {
    #expect(throws: ProviderFailure.self) {
        try ClaudeProfileResponse.parse(data(#"{"organization":{}}"#))
    }
}
