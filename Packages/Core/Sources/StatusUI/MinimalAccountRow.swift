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

    @ObservedObject private var loc: Localization

    public init(
        snapshot: AccountSnapshot,
        now: Date,
        choice: PrimaryWindow,
        showSnapshotAge: Bool,
        localization: Localization
    ) {
        self.snapshot = snapshot
        self.now = now
        self.choice = choice
        self.showSnapshotAge = showSnapshotAge
        self.loc = localization
    }

    private var window: LimitWindow? { snapshot.headlineWindow(for: choice) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            line
            if snapshot.failure == nil, let window { bar(window) }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 6)
        .help(tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(loc.spokenSummary(for: snapshot, now: now))
    }

    private var line: some View {
        HStack(spacing: 6) {
            Text(snapshot.displayName)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if let failure = snapshot.failure {
                Text(loc.failureText(failure.kind))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if let window {
                if snapshot.freshness.isStale && showSnapshotAge {
                    Text(capturedDate)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Text(loc.windowTitle(window.id))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text(loc.percent(window.percent))
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(window.severity.numberTint)
                Text(loc.remaining(window.remaining(from: now)))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    // Wide enough for "5 d 23 h" in the language that spells it
                    // longest, so the percentage beside it does not shuffle
                    // sideways every time a countdown changes unit.
                    .frame(width: 58, alignment: .trailing)
            }
        }
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
            ? AnyShapeStyle(.tertiary)
            : AnyShapeStyle(window.severity.tint)
    }

    /// Everything the row stopped drawing, in one tooltip: the service and the
    /// plan always, when the reading was taken if it is old, and the log's own
    /// sentence when there is a failure.
    private var tooltip: String {
        var parts = ["\(snapshot.provider.title) · \(snapshot.planLabel)"]
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
