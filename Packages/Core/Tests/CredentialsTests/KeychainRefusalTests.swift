import Testing
import Foundation
import Security
import ProviderKit
@testable import Credentials

/// The status that arrives is not the one the name suggests.
///
/// Reading an item another app owns with user interaction switched off returns
/// `errSecAuthFailed`, not `errSecInteractionNotAllowed`. Matching only the
/// obvious one meant the refusal was reported as an ordinary read failure — which
/// tells the reader to sign in again, the single action that cannot help — and
/// every screen built to explain the refusal never appeared.
///
/// Found by probing the running app: the CLI's keychain item answered -25293
/// while the app's own item answered 0.
@Suite struct RecognisingAKeychainRefusal {

    @Test func theStatusTheSystemActuallyReturnsIsARefusal() {
        let failure = KeychainRefusal.failure(for: errSecAuthFailed)
        #expect(failure?.kind == .needsPermission,
                "errSecAuthFailed (-25293) is what a blocked read answers with")
    }

    @Test func theDocumentedStatusIsAlsoARefusal() {
        #expect(KeychainRefusal.failure(for: errSecInteractionNotAllowed)?.kind == .needsPermission)
    }

    @Test func successIsNotARefusal() {
        #expect(KeychainRefusal.failure(for: errSecSuccess) == nil)
    }

    /// A missing item is handled before this is consulted and must not be
    /// mistaken for a permission problem: an account that was never stored is
    /// not one waiting to be allowed.
    @Test func aMissingItemIsNotARefusal() {
        #expect(KeychainRefusal.failure(for: errSecItemNotFound) == nil)
    }

    @Test func anUnrelatedFailureIsNotARefusal() {
        #expect(KeychainRefusal.failure(for: errSecDecode) == nil)
        #expect(KeychainRefusal.failure(for: errSecParam) == nil)
    }

    /// The diagnostic reaches a person through the row's tooltip, so it says
    /// which of the two it was.
    @Test func theTwoRefusalsAreToldApartInTheDiagnostic() {
        let blocked = KeychainRefusal.failure(for: errSecInteractionNotAllowed)?.diagnostic ?? ""
        let denied = KeychainRefusal.failure(for: errSecAuthFailed)?.diagnostic ?? ""
        #expect(blocked != denied)
        #expect(denied.contains("25293"))
    }
}
