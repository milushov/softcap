import Testing
import Credentials

/// Pressing Refresh is not consent to a password dialog.
///
/// The switch that lets the keychain ask used to go up for any poll a person
/// started, and the poll took the raised switch as its reason to open Claude
/// Code's item. On a machine where all four accounts held grants of the app's
/// own — nothing left that needed that item — every press of Refresh still put
/// the login-keychain password dialog on screen. "A person acted" and "a
/// person asked to open another app's item" are different consents, and only
/// the button that says "Allow access…" means the second one.
@Suite struct RefreshingIsNotConsentToADialog {

    @Test func aTimerMayNotRaiseTheDialog() {
        #expect(!PollOrigin.timer.mayRaiseTheKeychainDialog)
    }

    /// The case this table exists for: it used to be `true`.
    @Test func aPersonsRefreshMayNotRaiseTheDialogEither() {
        #expect(!PollOrigin.person.mayRaiseTheKeychainDialog)
    }

    @Test func onlyTheExplicitGrantMay() {
        #expect(PollOrigin.allowingAccess.mayRaiseTheKeychainDialog)
    }
}
