import SwiftUI
import ProviderKit

/// What a window can do about a row that says a sign-in is required.
///
/// Handed in by the app, and `nil` everywhere else. The same row is drawn by
/// four surfaces and only one of them has a browser to send anybody to: a
/// widget is a timeline of pictures, and a button in a picture is a picture of
/// a button. So the offer is a parameter rather than something the row reaches
/// for, and a surface that cannot act simply does not pass one.
///
/// The words are not in here. The row builds them from `Progress` and the
/// snapshot's own provider, because they belong in the catalogues with every
/// other sentence this app shows — see `signInState(_:provider:)` below.
public struct SignInOffer {

    /// How far along the one sign-in this app runs at a time has got.
    public enum Progress: Sendable, Hashable {
        /// Nothing is running. This row can start one.
        case offered
        /// A sign-in is running for somebody else. One at a time is the
        /// controller's rule and not an arbitrary one — two attempts would
        /// share a callback port and a browser, and the second would take the
        /// first one's reply.
        case blocked
        /// The browser has it.
        case running
        /// The keychain write, which cannot be interrupted or rolled back.
        /// Offering to cancel here would be offering something that is not
        /// true.
        case saving
    }

    public let progress: Progress

    /// What the last attempt said, if it said anything — already translated,
    /// because the controller builds it from the failure it met.
    ///
    /// Without it a sign-in that failed leaves the row saying exactly what it
    /// said before anybody pressed anything, which is indistinguishable from
    /// the press having done nothing at all.
    public let note: String?

    public let start: () -> Void
    public let cancel: () -> Void

    public init(
        progress: Progress,
        note: String? = nil,
        start: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) {
        self.progress = progress
        self.note = note
        self.start = start
        self.cancel = cancel
    }
}

public extension Localization {

    /// What a row says about the sign-in it is carrying.
    ///
    /// Every one of these keys was already in the ten catalogues, written for
    /// the Accounts screen. The window says the same things in the same words
    /// on purpose: somebody who has seen one screen should not have to work out
    /// that the other means the same thing.
    func signInState(_ progress: SignInOffer.Progress, provider: ProviderID) -> String {
        switch progress {
        case .offered, .blocked: self("Sign-in required")
        case .running:           String(format: self("Signing in to %@…"), provider.title)
        case .saving:            self("Saving account…")
        }
    }
}

/// The offer, drawn.
///
/// One view for both windows rather than one each, with `compact` for the
/// difference: the full window has a line of its own to spend and says what is
/// happening beside the button, and the minimal window has the right-hand end
/// of one line and spends it on the button alone. That window's whole argument
/// is that everything which is not a reading comes off the screen — so the
/// sentence goes to its tooltip, where `MinimalAccountRow` already keeps the
/// service, the plan and the diagnostic.
struct SignInPrompt: View {
    let offer: SignInOffer
    let provider: ProviderID
    let compact: Bool

    @ObservedObject var loc: Localization

    var body: some View {
        if compact {
            HStack(spacing: 6) {
                if isWorking { ProgressView().controlSize(.small) }
                action
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(loc.signInState(offer.progress, provider: provider))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if isWorking { ProgressView().controlSize(.small) }
                    Spacer(minLength: 4)
                    action
                }
                if let note = offer.note {
                    Text(note)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var isWorking: Bool {
        offer.progress == .running || offer.progress == .saving
    }

    /// Plain rather than bordered, in both windows. The limits window has three
    /// plain buttons in its footer and no bordered ones anywhere; one here
    /// would be the only framed control on screen, sitting inside a row whose
    /// other contents are all text.
    @ViewBuilder
    private var action: some View {
        switch offer.progress {
        case .offered, .blocked:
            button(loc("Sign in…"), enabled: offer.progress == .offered, offer.start)
        case .running, .saving:
            button(loc("Cancel"), enabled: offer.progress == .running, offer.cancel)
        }
    }

    private func button(
        _ title: String, enabled: Bool, _ act: @escaping () -> Void
    ) -> some View {
        Button(title) { act() }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            // The tint is worked out rather than left to `.disabled`, which
            // greys a bordered button and does nothing visible to a plain one:
            // the button would have looked exactly as pressable while it was
            // refusing to be pressed.
            .foregroundStyle(enabled ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
            .disabled(!enabled)
            // Otherwise the first button in the window takes keyboard focus on
            // opening and the system draws an accent-coloured fill behind it —
            // the same thing `PopoverView.quietButton` guards against, for the
            // same reason and with the same one line.
            .focusEffectDisabled()
            // The fill and the hand, and neither when the button is refusing
            // to be pressed — for which this has to be told, exactly as the
            // tint above has to be: `.disabled` does nothing visible to a
            // plain button.
            .clickAffordance(enabled: enabled)
    }
}

public extension View {

    /// The offer, for VoiceOver.
    ///
    /// An account row collapses into a single spoken element — `Accessibility`
    /// explains why — and a button inside a collapsed element cannot be reached
    /// at all. An action named on the element itself can: it arrives in the
    /// actions rotor, which is where VoiceOver looks for what can be done to
    /// the thing being read rather than for another thing to read.
    ///
    /// Both buttons, not just the first. Offering the sign-in and not the
    /// cancel would leave somebody able to start an attempt from this window
    /// and unable to stop it — waiting out a five-minute timeout for a press
    /// they could see the consequence of and not reach. `.saving` names no
    /// action, which is the truth: that write cannot be called back.
    @ViewBuilder
    func accessibilitySignIn(
        _ offer: SignInOffer?, named title: String, cancel: String
    ) -> some View {
        if let offer, offer.progress == .offered {
            accessibilityAction(named: Text(title), offer.start)
        } else if let offer, offer.progress == .running {
            accessibilityAction(named: Text(cancel), offer.cancel)
        } else {
            self
        }
    }
}
