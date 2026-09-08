import Testing
import Foundation
import CryptoKit
@testable import ClaudeProvider

@Test func challengeIsBase64URLOfSHA256OfVerifier() throws {
    let pair = try #require(PKCEPair.generate())
    let expected = Data(SHA256.hash(data: Data(pair.verifier.utf8)))
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    #expect(pair.challenge == expected)
}

@Test func encodingIsURLSafeAndUnpadded() throws {
    for _ in 0..<50 {
        let pair = try #require(PKCEPair.generate())
        for value in [pair.verifier, pair.challenge] {
            #expect(value.contains("+") == false)
            #expect(value.contains("/") == false)
            #expect(value.contains("=") == false)
        }
    }
}

@Test func verifierIsLongEnoughForTheSpec() throws {
    // RFC 7636 asks for 43 to 128 characters.
    let pair = try #require(PKCEPair.generate())
    #expect(pair.verifier.count >= 43)
    #expect(pair.verifier.count <= 128)
}

@Test func eachPairIsDifferent() throws {
    let first = try #require(PKCEPair.generate())
    let second = try #require(PKCEPair.generate())
    #expect(first.verifier != second.verifier)
}
