import Testing
import Foundation
import ProviderKit
@testable import CodexProvider

/// Builds an unsigned JWT: only the body is parsed, the signature is never checked.
private func makeIDToken(_ payload: [String: Any]) -> String {
    let body = try! JSONSerialization.data(withJSONObject: payload)
    let encoded = body.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "header.\(encoded).signature"
}

private func makeAuthJSON(_ payload: [String: Any]) -> Data {
    let json: [String: Any] = ["auth_mode": "chatgpt", "tokens": ["id_token": makeIDToken(payload)]]
    return try! JSONSerialization.data(withJSONObject: json)
}

@Test func readsNamePlanAndAccount() throws {
    let data = makeAuthJSON([
        "name": "Tyler Durden",
        "email": "tyler@example.com",
        "https://api.openai.com/auth": [
            "chatgpt_plan_type": "plus",
            "chatgpt_account_id": "d4c3b2a1-f6e5-4b7a-9c8d-5d4c3b2a1f0e",
        ],
    ])
    let identity = try CodexIdentityReader.parse(authJSON: data)
    #expect(identity.displayName == "Tyler Durden")
    #expect(identity.planType == "plus")
    #expect(identity.accountID == "d4c3b2a1-f6e5-4b7a-9c8d-5d4c3b2a1f0e")
}

@Test func fallsBackToEmailWhenNameMissing() throws {
    let data = makeAuthJSON([
        "email": "tyler@example.com",
        "https://api.openai.com/auth": ["chatgpt_plan_type": "pro", "chatgpt_account_id": "acc-1"],
    ])
    let identity = try CodexIdentityReader.parse(authJSON: data)
    #expect(identity.displayName == "tyler@example.com")
}

@Test func fallsBackToAccountIDWhenNothingElseIsThere() throws {
    let data = makeAuthJSON(["https://api.openai.com/auth": ["chatgpt_account_id": "acc-42"]])
    let identity = try CodexIdentityReader.parse(authJSON: data)
    #expect(identity.displayName == "acc-42")
    #expect(identity.planType == nil)
}

@Test func rejectsTokenThatIsNotAJWT() {
    let json: [String: Any] = ["tokens": ["id_token": "nodots"]]
    let data = try! JSONSerialization.data(withJSONObject: json)
    #expect(throws: ProviderFailure.self) { try CodexIdentityReader.parse(authJSON: data) }
}

@Test func rejectsAuthFileWithoutTokens() {
    let data = try! JSONSerialization.data(withJSONObject: ["auth_mode": "apikey"])
    #expect(throws: ProviderFailure.self) { try CodexIdentityReader.parse(authJSON: data) }
}
