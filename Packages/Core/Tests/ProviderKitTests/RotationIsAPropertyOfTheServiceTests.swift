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

    /// Two, and each for its own reason: a device grant for a public GitHub
    /// client has nothing to rotate, and a coding-plan key is handed over whole
    /// and never expires on its own.
    @Test func theStaticServicesAreNamedAndAreTheOnlyOnes() {
        #expect(Set(ProviderID.allCases.filter { !$0.rotatesCredentials }) == [.copilot, .glm])
    }

    /// `true` is the answer for anything not yet implemented, because of the
    /// two possible mistakes it is the visible one: a rotating service wrongly
    /// marked static goes on serving a token the server has retired, which
    /// arrives as an unexplained failure; a static service wrongly marked
    /// rotating asks for a sign-in that plainly works.
    @Test func theServicesNotYetBuiltClaimTheVisibleMistake() {
        for provider in [ProviderID.cursor, .gemini] {
            #expect(provider.rotatesCredentials, """
                \(provider.rawValue) is not implemented and claims it does not rotate, \
                which is the mistake that fails silently
                """)
        }
    }
}
