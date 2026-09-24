import SwiftUI
import ProviderKit
import Preferences

/// One account's row. Shared by the limits window and the widget: a copy in two
/// places would drift apart on the first edit.
///
/// Takes ready data rather than an app model, which is why the widget extension
/// can use it — it has no app process of its own.
public struct AccountRow: View {
    private let snapshot: AccountSnapshot
    private let now: Date
    private let layout: RowLayout
    private let showSnapshotAge: Bool
    private let compactPadding: Bool

    /// What the window can do about a row that needs a sign-in, when the
    /// surface drawing it can do anything at all. `nil` in both widgets and on
    /// the phone — see `SignInOffer`.
    private let signIn: SignInOffer?

    @ObservedObject private var loc: Localization
    @Environment(\.layoutDirection) private var direction

    public init(
        snapshot: AccountSnapshot,
        now: Date,
        layout: RowLayout = .twoWindows,
        showSnapshotAge: Bool = true,
        compactPadding: Bool = false,
        localization: Localization,
        signIn: SignInOffer? = nil
    ) {
        self.snapshot = snapshot
        self.now = now
        self.layout = layout
        self.showSnapshotAge = showSnapshotAge
        self.compactPadding = compactPadding
        self.loc = localization
        self.signIn = signIn
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: compactPadding ? 5 : 7) {
            header
            if let failure = snapshot.failure {
                // A dead token is the one failure a person can do something
                // about without leaving the window, so it is the one failure
                // the row offers to act on. The network being down and a
                // response nobody can parse are still sentences and nothing
                // more: a button that cannot help is worse than no button.
                if failure.kind == .needsLogin, let signIn {
                    SignInPrompt(
                        offer: signIn, provider: snapshot.provider,
                        compact: false, loc: loc
                    )
                    .help(failure.diagnostic)
                } else {
                    Text(loc.failureText(failure.kind))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        // The reason, on hover. `diagnostic` is written for a
                        // log — untranslated, and carrying a status code or a
                        // path — and the row keeps saying the translated
                        // sentence instead. But a log nobody can open is a place
                        // information goes to be lost, and this one is worth a
                        // second's reach: three diagnoses in this project needed
                        // exactly this string and each had to be recovered by
                        // editing the app to write it to a file. A tooltip is
                        // invisible until somebody looks for it, which is the
                        // right amount of visible for a status code.
                        .help(failure.diagnostic)
                }
            } else {
                switch layout {
                case .twoWindows: ForEach(snapshot.windows) { meter(for: $0) }
                case .compact:    compactMeter
                case .rings:      ringsRow
                }
            }
        }
        .padding(.horizontal, compactPadding ? 0 : 13)
        .padding(.vertical, compactPadding ? 6 : 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(loc.spokenSummary(for: snapshot, now: now))
        .accessibilitySignIn(signIn, named: loc("Sign in…"), cancel: loc("Cancel"))
    }

    // MARK: - header

    private var header: some View {
        HStack(spacing: 9) {
            ProviderBadge(provider: snapshot.provider)
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.displayName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(snapshot.provider.title) · \(snapshot.planLabel)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if snapshot.freshness.isStale && showSnapshotAge {
                Text(staleLabel)
                    .font(.system(size: 9.5, weight: .semibold))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var staleLabel: String {
        let captured = snapshot.freshness.capturedAt
        guard captured > .distantPast else { return loc("no data") }
        let formatter = DateFormatter()
        formatter.locale = loc.activeLocale
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return String(format: loc("Data from %@"), formatter.string(from: captured))
    }

    // MARK: - layout A: two windows

    private func meter(for window: LimitWindow) -> some View {
        HStack(spacing: 8) {
            Text(loc.windowTitle(window.id))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)

            LimitBar(percent: window.percent)
                .frame(height: 4)

            Text(loc.percent(window.percent))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(window.severity.numberTint)
                // 38, not 34: languages that put a space before the sign need
                // 34.4 pt for "100 %" — it would have been cut off at exactly
                // the reading that matters most. The width comes out of the
                // bar, which is flexible.
                .frame(width: 38, alignment: .trailing)

            Text(loc.remaining(window.remaining(from: now)))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing)
        }
    }

    // MARK: - layout B: single line

    private var compactMeter: some View {
        // `bar`, not `weekly`. It holds whichever window fills the line, and
        // the fallback beside it means that is not always the weekly one — for
        // a service reporting a single monthly allowance it is that. The name
        // said otherwise and the label below was written from the name rather
        // than from the value, so the row read `week 42%` about a month.
        let bar = snapshot.windows.first { $0.id == "weekly" } ?? snapshot.windows.first
        let tick = snapshot.windows.first { $0.id == "session" }

        return VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    if let bar {
                        Capsule()
                            .fill(bar.severity.tint)
                            .frame(width: max(2, geo.size.width * bar.percent / 100))
                    }
                    if let tick {
                        // The five-hour tick. Under right-to-left writing the
                        // offset is measured from the other edge, so the sign
                        // flips — otherwise the mark leaves the bar.
                        let offset = geo.size.width * tick.percent / 100
                        Rectangle()
                            .fill(.primary.opacity(0.55))
                            .frame(width: 1.5, height: 7)
                            .offset(x: direction == .rightToLeft ? -offset : offset)
                    }
                }
            }
            .frame(height: 4)

            HStack(spacing: 6) {
                if let bar {
                    // The window's own identifier, as the other two layouts
                    // already ask for it. Written as a literal here, the label
                    // was a claim about the period rather than a reading of it.
                    Text("\(loc.windowTitle(bar.id)) \(loc.percent(bar.percent))")
                    Text(loc.remaining(bar.remaining(from: now)))
                }
                if let tick {
                    Text("· \(loc.windowTitle(tick.id)) \(loc.percent(tick.percent))")
                }
            }
            .font(.system(size: 10.5))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - layout C: rings

    private var ringsRow: some View {
        HStack(spacing: 10) {
            ForEach(snapshot.windows) { window in
                VStack(spacing: 3) {
                    ZStack {
                        Circle().stroke(.quaternary, lineWidth: 3.4)
                        Circle()
                            .trim(from: 0, to: max(0.01, window.percent / 100))
                            .stroke(window.severity.tint,
                                    style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
                            // Circular indicators are not mirrored in any
                            // system: clockwise reads the same whatever the
                            // writing direction.
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(window.percent.rounded()))")
                            .font(.system(size: 9.5, weight: .semibold))
                            .monospacedDigit()
                    }
                    .frame(width: 34, height: 34)
                    Text(loc.windowTitle(window.id))
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let worst = snapshot.peakWindow {
                Text(loc.remaining(worst.remaining(from: now)))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A fill bar. Separated out because under right-to-left writing it must fill
/// from the right edge — a `ZStack` anchored `.leading` is mirrored by the
/// system, but only when the anchor is `leading` rather than `left`.
public struct LimitBar: View {
    private let percent: Double

    public init(percent: Double) { self.percent = percent }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(Severity(percent: percent).tint)
                    .frame(width: max(2, geo.size.width * percent / 100))
            }
        }
    }
}

/// A service badge: a monochrome glyph, not a coloured plate. Colour already
/// encodes load in this window, and a second colour language weakens both.
public struct ProviderBadge: View {
    private let provider: ProviderID

    public init(provider: ProviderID) { self.provider = provider }

    public var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .strokeBorder(.quaternary, lineWidth: 1)
            .frame(width: 20, height: 20)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            )
    }

    private var symbol: String {
        switch provider {
        case .claude:  "sparkle"
        case .codex:   "circle.circle"
        case .cursor:  "cube"
        case .copilot: "chevron.left.forwardslash.chevron.right"
        case .gemini:  "diamond"
        }
    }
}
