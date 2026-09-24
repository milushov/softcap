import SwiftUI
import Credentials
import StatusUI

/// What the two screens say about a saved account list that would not open.
///
/// Both of them meet the same three reasons and have to say the same things
/// about each. The sentences lived on the settings screen, as a private
/// `switch` inside the pane that drew them — which was right while that pane was
/// the only place the situation could be read. It is not any more: the limits
/// window is where somebody who has just updated actually looks, and a second
/// `switch` there is two places to keep in agreement about what a refused
/// keychain means.
///
/// Here rather than in `StatusUI`, where the catalogues are. That target is what
/// the widgets are built from and it does not depend on `Credentials` — a
/// dependency added for three sentences would put the credential store inside a
/// timeline of pictures. The App target already imports both, and assembling
/// labels out of the catalogues is the UI layer's job.
@MainActor
struct SavedAccountsProblem {
    let reason: UnreadableAccountList
    private let loc: Localization

    init(_ reason: UnreadableAccountList, _ loc: Localization = .shared) {
        self.reason = reason
        self.loc = loc
    }

    /// The first thing read, and the one that has to be true.
    ///
    /// Two of the three reasons mean the accounts are coming back whole, and
    /// saying so is the single most useful sentence this app can put on that
    /// screen: what it replaced was "No accounts found", which is the opposite
    /// claim about the same accounts.
    ///
    /// The third is not that. A list this build opened and could not understand
    /// has one way on, and it deletes every refresh token in the item — so the
    /// heading there is the settings screen's older one, which states what
    /// happened and promises nothing.
    var heading: String {
        switch reason {
        case .keychainRefusedThisBuild, .keychainDidNotOpen:
            loc("Your accounts are still here")
        case .contentNotUnderstood:
            loc("Saved accounts could not be opened")
        }
    }

    /// Why, in the terms the person is standing in rather than the keychain's.
    ///
    /// Unchanged from the settings screen, deliberately and word for word:
    /// somebody who has read one screen should not have to work out that the
    /// other means the same thing. It runs to four lines in a window this
    /// narrow, where a sentence written for the window would run to two — and
    /// it says *why* as well as *what*, in ten languages that already exist.
    var explanation: String {
        switch reason {
        case .keychainRefusedThisBuild:
            loc("This copy of the app is not the one that saved them. The keychain will ask once — choose “Always Allow”.")
        case .keychainDidNotOpen:
            loc("The keychain did not open them. It may be locked.")
        case .contentNotUnderstood:
            loc("What is saved cannot be read by this version.")
        }
    }

    /// Whether putting the keychain's question to the person can help.
    ///
    /// An unlock is a question too, so a keychain that did not answer is worth
    /// asking. Only the list that opened and made no sense has nobody left to
    /// ask: there is no answer anybody could give that would make this build
    /// understand what is in there, and a button offering one would be a button
    /// that cannot work.
    var mayBeOpened: Bool {
        switch reason {
        case .keychainRefusedThisBuild, .keychainDidNotOpen: true
        case .contentNotUnderstood: false
        }
    }

    /// A lock for the two that open, a warning for the one that does not.
    ///
    /// The limits window draws it; the settings screen does not. That window has
    /// a column of its own to fill and nothing else in it, and the symbol is
    /// what stops four lines of explanation reading as an error report. The
    /// pane has a heading, a divider and the rest of a screen around it, and one
    /// symbol there would be the only one on the page.
    var symbol: String {
        mayBeOpened ? "lock.fill" : "exclamationmark.triangle.fill"
    }
}
