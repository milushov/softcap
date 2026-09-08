import WidgetKit
import SwiftUI
import ProviderKit
import Preferences
import Monitoring
import StatusUI

/// The widget adapts to the space it is given: more cells means more accounts
/// and more detail. The logic is one — only the capacity differs.
struct LimitsWidgetView: View {
    let entry: LimitsEntry

    @Environment(\.widgetFamily) private var family

    /// The language is set when the view is constructed, not in `onAppear`.
    ///
    /// A widget renders in a single pass: `onAppear` fires after the strings and
    /// writing direction have been computed, which made an Arabic snapshot come
    /// out English and left-to-right.
    private let loc: Localization

    init(entry: LimitsEntry) {
        self.entry = entry
        let localization = Localization()
        localization.use(AppLanguage(code: entry.snapshot?.languageCode))
        self.loc = localization
    }

    var body: some View {
        content
            // The chosen language decides how a date and a time are written, not
            // only which words are used. Left alone, SwiftUI formats them in the
            // system's language while every label around them follows the setting —
            // so the badge said `28 Aug` in one language and the clock beside it
            // read in another.
            .environment(\.locale, loc.activeLocale)
            .environment(\.layoutDirection, loc.layoutDirection ?? .leftToRight)
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot, !snapshot.accounts.isEmpty {
            switch family {
            case .systemSmall: compact(snapshot)
            default:           list(snapshot)
            }
        } else {
            empty
        }
    }

    // MARK: - small: only what matters most

    /// A list does not fit one cell, so we show what people open the widget for:
    /// the busiest account and when it frees up.
    private func compact(_ snapshot: SharedSnapshot) -> some View {
        let busiest = snapshot.accounts.max { $0.peakPercent < $1.peakPercent }
        let window = busiest?.peakWindow

        return VStack(alignment: .leading, spacing: 6) {
            // Overdue, the age takes the title's place. The title is inferable
            // from what is under it and from the widget's own name in the
            // gallery; a percentage nobody has checked in a day is not.
            HStack(spacing: 5) {
                Image(systemName: "gauge.with.needle").font(.system(size: 11))
                if case .overdue(let seconds) = age(of: snapshot) {
                    Text(String(format: loc("%@ old"), loc.remaining(seconds)))
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(Severity.hot.tint)
                } else {
                    Text(loc("Subscription limits"))
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if let busiest, let window {
                Text(loc.percent(window.percent))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(window.severity.tint)
                Text(busiest.displayName)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Text(loc.remaining(window.remaining(from: entry.date)))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// When the figures were taken, and whether that is longer ago than it
    /// should be.
    ///
    /// This showed `entry.date` — the moment the timeline entry was built, which
    /// is *now*. On a Mac that has been asleep, or where the app is not running,
    /// the widget printed the current time beside week-old percentages, which
    /// asserts a freshness the numbers do not have. The window next door had
    /// already worked this out and says so in its own comment: "2:41 AM is
    /// perfectly plausible and says nothing."
    ///
    /// Same vocabulary as the window, deliberately: the age in the hot tint once
    /// it is overdue, the time it was taken otherwise. The widget cannot show a
    /// tooltip, so the words have to carry it alone.
    private func age(of snapshot: SharedSnapshot) -> ReadingAge {
        readingAge(
            lastUpdated: snapshot.capturedAt, now: entry.date,
            pollingEvery: snapshot.pollingEvery ?? Preferences.defaults.backgroundInterval
        )
    }

    @ViewBuilder
    private func freshness(of snapshot: SharedSnapshot) -> some View {
        if case .overdue(let seconds) = age(of: snapshot) {
            Text(String(format: loc("%@ old"), loc.remaining(seconds)))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(Severity.hot.tint)
        } else {
            Text(snapshot.capturedAt, style: .time)
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - the rest: a list of as many as fit

    private func list(_ snapshot: SharedSnapshot) -> some View {
        let visible = Array(snapshot.accounts.prefix(capacity))
        let hidden = snapshot.accounts.count - visible.count

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(loc("Subscription limits"))
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                freshness(of: snapshot)
            }
            .padding(.bottom, 6)

            ForEach(visible) { account in
                AccountRow(
                    snapshot: account,
                    now: entry.date,
                    layout: snapshot.rowLayout,
                    showSnapshotAge: snapshot.showSnapshotAge && family != .systemMedium,
                    compactPadding: true,
                    localization: loc
                )
                if account.id != visible.last?.id { Divider().opacity(0.4) }
            }

            Spacer(minLength: 0)

            // Truncating silently is not acceptable: it would read as having
            // fewer accounts than there are.
            if hidden > 0 {
                Text(String(format: loc("+%lld more"), hidden))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// How many rows fit. The numbers are tuned to macOS cell heights: a row
    /// with two windows takes about 44 pt.
    private var capacity: Int {
        switch family {
        case .systemSmall:      1
        case .systemMedium:     2
        case .systemLarge:      6
        case .systemExtraLarge: 8
        default:                4
        }
    }

    private var empty: some View {
        VStack(spacing: 5) {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 18))
                .foregroundStyle(.tertiary)
            Text(loc("No accounts found"))
                .font(.system(size: 11, weight: .medium))
            Text(loc("Open Softcap to load data."))
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
