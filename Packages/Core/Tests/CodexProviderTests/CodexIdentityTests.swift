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

@Test func readsNamePlanAndAccount() throws {
    let token = makeIDToken([
        "name": "Tyler Durden",
        "email": "tyler@example.com",
        "https://api.openai.com/auth": [
            "chatgpt_plan_type": "plus",
            "chatgpt_account_id": "d4c3b2a1-f6e5-4b7a-9c8d-5d4c3b2a1f0e",
        ],
    ])
    let identity = try CodexIdentityReader.parse(idToken: token)
    #expect(identity.displayName == "Tyler Durden")
    #expect(identity.planType == "plus")
    #expect(identity.accountID == "d4c3b2a1-f6e5-4b7a-9c8d-5d4c3b2a1f0e")
}

@Test func fallsBackToEmailWhenNameMissing() throws {
    let token = makeIDToken([
        "email": "tyler@example.com",
        "https://api.openai.com/auth": ["chatgpt_plan_type": "pro", "chatgpt_account_id": "acc-1"],
    ])
    let identity = try CodexIdentityReader.parse(idToken: token)
    #expect(identity.displayName == "tyler@example.com")
}

@Test func fallsBackToAccountIDWhenNothingElseIsThere() throws {
    let token = makeIDToken(["https://api.openai.com/auth": ["chatgpt_account_id": "acc-42"]])
    let identity = try CodexIdentityReader.parse(idToken: token)
    #expect(identity.displayName == "acc-42")
    #expect(identity.planType == nil)
}

/// The account id may arrive beside the token rather than inside it: the code
/// exchange returns both, and the one outside wins.
@Test func prefersTheAccountIDHandedInOverTheClaim() throws {
    let token = makeIDToken(["https://api.openai.com/auth": ["chatgpt_account_id": "from-claim"]])
    let identity = try CodexIdentityReader.parse(idToken: token, accountID: "handed-in")
    #expect(identity.accountID == "handed-in")
}

@Test func rejectsTokenThatIsNotAJWT() {
    #expect(throws: ProviderFailure.self) { try CodexIdentityReader.parse(idToken: "nodots") }
}

@Test func rejectsTokenWithoutAnAccountID() {
    let token = makeIDToken(["name": "Tyler Durden"])
    #expect(throws: ProviderFailure.self) { try CodexIdentityReader.parse(idToken: token) }
}
