import SwiftUI
import ProviderKit
import Preferences

/// One account on one line: name, which limit, how full, how long left, and a
/// hairline under it.
///
/// A separate view rather than a fourth `RowLayout`. That enum describes a row;
/// the setting behind this one also takes away the window's header, its
/// dividers and its footer labels, and a single setting governing two scopes is
/// the kind nobody can predict from its name.
///
/// Colour is spent once and only when there is something to say: the bar and
/// the percentage stay grey while `Severity` is `.ok`. The service badge and
/// the plan label are not drawn at all — they are in the tooltip, which is the
/// same place this project already keeps `ProviderFailure.diagnostic`.
///
/// VoiceOver is unaffected: the row reads as the same sentence the full one
/// does, both windows included. This setting takes things off the screen, not
/// out of the app.
public struct MinimalAccountRow: View {
    private let snapshot: AccountSnapshot
    private let now: Date
    private let choice: PrimaryWindow
    private let showSnapshotAge: Bool

    /// See `AccountRow`. `nil` on every surface that has no browser to send
    /// anybody to, which is every surface but this window.
    private let signIn: SignInOffer?

    @ObservedObject private var loc: Localization

    /// A click on the period label, and nothing longer-lived than that. `nil`
    /// obeys the `Primary window` setting; `.session`/`.weekly` is somebody
    /// peeking at the row's other period. Deliberately not a preference:
    /// remembering it would quietly turn one curious click into a changed
    /// default, so the window forgets it on closing — explicitly, in
    /// `onDisappear`, because the popover is cached and this view's state
    /// survives between openings. A changed `Primary window` setting drops it
    /// the same way: the new answer outranks the look.
    @State private var peek: PrimaryWindow?

    public init(
        snapshot: AccountSnapshot,
        now: Date,
        choice: PrimaryWindow,
        showSnapshotAge: Bool,
        localization: Localization,
        signIn: SignInOffer? = nil
    ) {
        self.snapshot = snapshot
        self.now = now
        self.choice = choice
        self.showSnapshotAge = showSnapshotAge
        self.loc = localization
        self.signIn = signIn
    }

    private var window: LimitWindow? { snapshot.headlineWindow(for: peek ?? choice) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            line
            if snapshot.failure == nil, let window { bar(window) }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 6)
        .help(tooltip)
        .onDisappear { peek = nil }
        // A new answer in Settings outranks a passing look: the Appearance
        // pane pins this popover open as its live preview, so without this
        // line a peeked row would sit beside the `Primary window` picker
        // contradicting it.
        .onChange(of: choice) { peek = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(loc.spokenSummary(for: snapshot, now: now))
        .accessibilitySignIn(signIn, named: loc("Sign in…"), cancel: loc("Cancel"))
    }

    private var line: some View {
        HStack(spacing: 6) {
            Text(snapshot.displayName)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if let failure = snapshot.failure {
                // The only failure with a way out, and the way out is the whole
                // right-hand end of the line. What is happening goes to the
                // tooltip below, where this window already keeps the service,
                // the plan and the diagnostic.
                if failure.kind == .needsLogin, let signIn {
                    SignInPrompt(
                        offer: signIn, provider: snapshot.provider,
                        compact: true, loc: loc
                    )
                } else {
                    Text(loc.failureText(failure.kind))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else if let window {
                if snapshot.freshness.isStale && showSnapshotAge {
                    Text(capturedDate)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                // Three columns rather than three words, so that the rows read
                // down the window as well as across. Each is as wide as the
                // widest thing it can ever hold, and is sized by drawing that
                // thing hidden underneath rather than by a number of points:
                // the widest is a different word and a different numeral in
                // each of ten languages, and a measurement in points is the
                // one thing that cannot survive being translated.
                //
                // What it fixes is small and was on every screenshot: a row at
                // a hundred percent spells three digits where the row under it
                // spells two, so the period label beside it sat further left
                // by the width of a digit, in a window whose whole point is
                // four short lines that can be read at a glance.
                ZStack(alignment: .trailing) {
                    widestPeriod.hidden()
                    periodLabel(window)
                }
                ZStack(alignment: .trailing) {
                    percentText(loc.percent(100)).hidden()
                    percentText(loc.percent(window.percent))
                        .foregroundStyle(window.severity.numberTint)
                }
                Text(loc.remaining(window.remaining(from: now)))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    // Wide enough for "5 d 23 h" in the language that spells it
                    // longest, so the percentage beside it does not shuffle
                    // sideways every time a countdown changes unit.
                    .frame(width: 58, alignment: .trailing)
            }
        }
    }

    /// The period label, clickable when the row has another period to show.
    ///
    /// The click flips only its own row — with `Busiest` the rows' labels
    /// already differ, so a whole-window flip would have no honest meaning.
    /// The percentage, the remaining time and the bar all follow, because
    /// every one of them is computed from the single `window` this row
    /// resolves. VoiceOver is deliberately untouched: the row collapses into
    /// `spokenSummary`, which already reads both periods, so the click
    /// reveals nothing a listener was missing.
    @ViewBuilder
    private func periodLabel(_ window: LimitWindow) -> some View {
        if snapshot.hasAnotherPeriod {
            Button { peek = snapshot.peek(after: window, setting: choice) } label: {
                periodText(window)
            }
            .buttonStyle(.plain)
            // The same line `SignInPrompt` and `quietButton` carry, for the
            // same reason: the first button in the popover otherwise opens
            // wearing the accent-coloured focus fill.
            .focusEffectDisabled()
            // The fill and the hand, and with them the explicit forgetting of
            // the hover that the popover being cached requires. See
            // `ClickAffordance`, which also explains why it takes up no room:
            // this label is a column, and a column that widened under the
            // pointer would move the two beside it.
            .clickAffordance()
        } else {
            periodText(window)
        }
    }

    private func periodText(_ window: LimitWindow) -> some View {
        Text(loc.windowTitle(window.id))
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
    }

    /// The period column's width: whichever of the two words is longer in the
    /// language on screen. Drawn to be measured, never seen — the row collapses
    /// into one spoken element, so there is nothing here for VoiceOver to read
    /// twice.
    private var widestPeriod: some View {
        ZStack {
            Text(loc.windowTitle("session"))
            Text(loc.windowTitle("weekly"))
        }
        .font(.system(size: 10))
    }

    /// The percentage column's, the same way: `100%` is the widest it goes.
    private func percentText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .monospacedDigit()
    }

    /// Grey until it matters. `LimitBar` is not reused: it paints every
    /// percentage, which is right in the full window and is the one habit this
    /// window exists to drop.
    private func bar(_ window: LimitWindow) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(paint(window))
                    .frame(width: max(2, geo.size.width * window.percent / 100))
            }
        }
        .frame(height: 2)
    }

    /// The bar's fill, which is not the number's colour: see `numberTint`.
    private func paint(_ window: LimitWindow) -> AnyShapeStyle {
        window.severity == .ok
            ? AnyShapeStyle(.secondary)
            : AnyShapeStyle(window.severity.tint)
    }

    /// Everything the row stopped drawing, in one tooltip: the service and the
    /// plan always, when the reading was taken if it is old, and the log's own
    /// sentence when there is a failure.
    private var tooltip: String {
        var parts = ["\(snapshot.provider.title) · \(snapshot.planLabel)"]
        // Where the full window's sentence went. Without it the only thing this
        // row says during a sign-in is a spinner and the word Cancel, and a
        // spinner does not say which of the two services it is waiting on.
        if let signIn {
            parts.append(loc.signInState(signIn.progress, provider: snapshot.provider))
            if let note = signIn.note { parts.append(note) }
        }
        if snapshot.freshness.isStale {
            parts.append(String(format: loc("Data from %@"), capturedDate))
        }
        if let failure = snapshot.failure, !failure.diagnostic.isEmpty {
            parts.append(failure.diagnostic)
        }
        return parts.joined(separator: "\n")
    }

    private var capturedDate: String {
        let captured = snapshot.freshness.capturedAt
        guard captured > .distantPast else { return loc("no data") }
        let formatter = DateFormatter()
        formatter.locale = loc.activeLocale
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: captured)
    }
}
