import Testing
import ProviderKit

/// Which services hand out something to rotate, and which do not.
///
/// The store reads this to decide what an account holding no refresh token
/// means, and the two answers are opposite. For a rotating service it is a
/// grant that has been spent, and refusing it is what stops a dead account
/// being retried on every poll until somebody notices. For a service that does
/// not rotate it is the ordinary resting state of an account that works, and
/// refusing it would say "sign in again" about a credential that answers —
/// forever, because the next sign-in produces one of exactly the same shape.
///
/// The claim lives here rather than beside either provider's own tests. It is
/// about `ProviderID` and it is about *all* of them: written in one provider's
/// file it said "only the device grant does not rotate", which stopped being
/// true the moment a second one arrived, in a file nobody editing the second
/// one would think to open.
@Suite struct RotationIsAPropertyOfTheService {

    /// Three, and each for its own reason: a device grant for a public GitHub
    /// client has nothing to rotate, and a coding-plan key — Z.ai's or Kimi's —
    /// is handed over whole and never expires on its own.
    @Test func theStaticServicesAreNamedAndAreTheOnlyOnes() {
        #expect(Set(ProviderID.allCases.filter { !$0.rotatesCredentials }) == [.copilot, .glm, .kimi])
    }

    /// The services that have a reader written for them. Everything else in
    /// the enum is named and not yet reachable.
    ///
    /// This is the list that has to be edited when a service is *implemented*,
    /// which is the direction that keeps the check honest: a new case joins the
    /// group below by doing nothing, so it is checked the moment it exists.
    private static let implemented: Set<ProviderID> = [.claude, .codex, .copilot, .glm, .kimi]

    /// `true` is the answer for anything not yet implemented, because of the
    /// two possible mistakes it is the visible one: a rotating service wrongly
    /// marked static goes on serving a token the server has retired, which
    /// arrives as an unexplained failure; a static service wrongly marked
    /// rotating asks for a sign-in that plainly works.
    ///
    /// Derived rather than listed. It was written as `[.cursor, .gemini]` —
    /// the same per-provider list this file was created to get rid of, in the
    /// file that got rid of it, where a seventh case would have passed in
    /// silence.
    @Test func theServicesNotYetBuiltClaimTheVisibleMistake() {
        let waiting = ProviderID.allCases.filter { !Self.implemented.contains($0) }
        #expect(!waiting.isEmpty, "nothing is waiting; this check now proves nothing")

        for provider in waiting {
            #expect(provider.rotatesCredentials, """
                \(provider.rawValue) is not implemented and claims it does not rotate, \
                which is the mistake that fails silently
                """)
        }
    }
}

/// The two flags a credential carries, and the one thing they may not say
/// together.
@Suite struct TheTwoCredentialFlagsAgree {

    /// A credential handed over was never granted, so there is nothing to
    /// rotate it with. Claiming both would have the store looking for a
    /// refresher that cannot exist and reporting "sign in again" about a key
    /// that works — which is the failure `rotatesCredentials` was added to
    /// prevent, arrived at from the other side.
    @Test func nothingGivenByHandAlsoRotates() {
        for provider in ProviderID.allCases where provider.credentialIsGivenByHand {
            #expect(!provider.rotatesCredentials, """
                \(provider.rawValue) says its credential is handed over and that it \
                rotates; a credential nobody granted has nothing to rotate with
                """)
        }
    }

    /// And the check is not vacuous: one service does hand its credential over.
    @Test func atLeastOneServiceIsAskedForItsKey() {
        #expect(ProviderID.allCases.contains { $0.credentialIsGivenByHand })
    }
}
