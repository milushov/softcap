import Testing
import Foundation
@testable import Diagnostics

/// The scrubber is the reason this module is allowed to exist at all, so it is
/// tested the way the promise on the landing page is: with the exact shapes that
/// would break it, not with a sample of pleasant ones.
@Suite struct ScrubberRemovesWhatItMustNotSend {

    /// Vacuous otherwise: an empty rule table redacts nothing and passes every
    /// test that only checks for absence.
    @Test func redactionRulesAllCompile() {
        #expect(Scrubber.ruleCount >= 7,
                "a rule failed to compile and was dropped — \(Scrubber.ruleCount) are in force")
    }

    /// The fixture is assembled rather than written out. `NoPersonalDataInTheRepository`
    /// forbids a home path anywhere in the repository, including inside the test
    /// that proves home paths are removed — which is the rule working, not a
    /// rule getting in the way.
    @Test func theHomeDirectoryStopsNamingThePerson() {
        let home = "/Users/" + "someone"
        let cleaned = Scrubber.clean("could not read \(home)/.claude/credentials.json")
        #expect(!cleaned.contains("someone"))
        // The rest of the path is what makes the report worth having.
        #expect(cleaned.contains(".claude/credentials.json"))
    }

    @Test func linuxHomeDirectoriesGoToo() {
        let home = "/home/" + "someone"
        #expect(!Scrubber.clean("\(home)/.codex/auth.json").contains("someone"))
    }

    @Test func anthropicKeysAreRemoved() {
        // Assembled for the same reason as the home path above: a credential
        // shape is forbidden in the repository even as a fixture.
        let key = "sk-ant-" + "api03-AbCdEfGh1234wxyz"
        let cleaned = Scrubber.clean("refresh rejected for \(key)")
        #expect(!cleaned.contains("api03-AbCdEfGh"))
        #expect(cleaned.contains("<token>") || cleaned.contains("<redacted>"))
    }

    @Test func jsonWebTokensAreRemoved() {
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NSJ9.dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1g"
        let cleaned = Scrubber.clean("Authorization failed: \(jwt)")
        #expect(!cleaned.contains("eyJhbGciOiJIUzI1NiJ9"))
    }

    @Test func addressesAreRemoved() {
        let cleaned = Scrubber.clean("account someone@example.com is out of quota")
        #expect(!cleaned.contains("@example.com"))
        #expect(cleaned.contains("<email>"))
    }

    /// The rule that catches what the others cannot know in advance: an opaque
    /// value is indistinguishable from a request id until the word beside it
    /// says otherwise.
    @Test func aValueLabelledLikeASecretGoesEvenWhenItsShapeIsUnknown() {
        for line in [
            "refresh_token: 9f8a7b6c5d4e3f2a1b",
            "password=hunter2",
            "api_key = ZmFrZS1rZXktdmFsdWU",
            "Bearer abc123def456",
        ] {
            let cleaned = Scrubber.clean(line)
            #expect(cleaned.contains("<redacted>"), "not redacted: \(line) -> \(cleaned)")
        }
    }

    /// Over-redaction is the intended failure mode, but it must not eat the
    /// sentence around it — a report that says only "<redacted>" is useless.
    @Test func ordinaryDiagnosticsSurviveIntact() {
        let text = "request failed: URLError -1009"
        #expect(Scrubber.clean(text) == text)
    }
}
