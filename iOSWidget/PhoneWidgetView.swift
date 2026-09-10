import WidgetKit
import SwiftUI
import ProviderKit
import Preferences
import Monitoring
import StatusUI

/// The phone widget. Shares the account row with the app and the Mac, and adds
/// the two accessory shapes a lock screen allows.
struct PhoneWidgetView: View {
    let entry: PhoneEntry

    @Environment(\.widgetFamily) private var family

    /// Set at construction rather than in `onAppear`: a widget renders in one
    /// pass, so anything applied later misses the strings and layout direction.
    private let loc: Localization

    init(entry: PhoneEntry) {
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
            case .accessoryCircular:    circular(snapshot)
            case .accessoryRectangular: rectangular(snapshot)
            case .systemSmall:          compact(snapshot)
            default:                    list(snapshot)
            }
        } else {
            empty
        }
    }

    /// The busiest window across all accounts — the number the whole app exists
    /// to answer.
    private func busiest(_ snapshot: SharedSnapshot) -> (AccountSnapshot, LimitWindow)? {
        guard let account = snapshot.accounts.max(by: { $0.peakPercent < $1.peakPercent }),
              let window = account.peakWindow
        else { return nil }
        return (account, window)
    }

    // MARK: - lock screen

    /// A ring with one number. There is room for nothing else, so it shows the
    /// figure that decides whether you can work at all.
    private func circular(_ snapshot: SharedSnapshot) -> some View {
        let worst = busiest(snapshot)
        return Gauge(value: (worst?.1.percent ?? 0) / 100) {
            Image(systemName: "gauge.with.needle")
        } currentValueLabel: {
            Text("\(Int((worst?.1.percent ?? 0).rounded()))")
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircular)
    }

    private func rectangular(_ snapshot: SharedSnapshot) -> some View {
        let worst = busiest(snapshot)
        return VStack(alignment: .leading, spacing: 1) {
            Text(loc("Subscription limits"))
                .font(.headline)
                .lineLimit(1)
            if let (account, window) = worst {
                Text("\(account.displayName) · \(loc.percent(window.percent))")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(loc.remaining(window.remaining(from: entry.date)))
                    .font(.caption2)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - home screen

    private func compact(_ snapshot: SharedSnapshot) -> some View {
        let worst = busiest(snapshot)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "gauge.with.needle").font(.system(size: 11))
                Text(loc("Subscription limits"))
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if let (account, window) = worst {
                Text(loc.percent(window.percent))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(window.severity.numberTint)
                Text(account.displayName)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Text(loc.remaining(window.remaining(from: entry.date)))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// When the figures were taken, and whether that is longer ago than it
    /// should be.
    ///
    /// This showed `entry.date`, the moment the timeline entry was built — the
    /// current time, printed beside however old the numbers happen to be. A
    /// phone whose app has not been opened in a week showed last week's
    /// percentages under this minute's clock. The Mac window says it best in its
    /// own comment: "2:41 AM is perfectly plausible and says nothing."
    @ViewBuilder
    private func freshness(of snapshot: SharedSnapshot) -> some View {
        let age = readingAge(
            lastUpdated: snapshot.capturedAt, now: entry.date,
            pollingEvery: snapshot.pollingEvery ?? Preferences.defaults.backgroundInterval
        )
        if case .overdue(let seconds) = age {
            Text(String(format: loc("%@ old"), loc.remaining(seconds)))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(Severity.hot.tint)
        } else {
            Text(snapshot.capturedAt, style: .time)
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func list(_ snapshot: SharedSnapshot) -> some View {
        let visible = Array(snapshot.accounts.prefix(family == .systemMedium ? 2 : 5))
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

            // Never truncate silently: it would read as having fewer accounts.
            if hidden > 0 {
                Text(String(format: loc("+%lld more"), hidden))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var empty: some View {
        VStack(spacing: 5) {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            Text(loc("No accounts found"))
                .font(.system(size: 11, weight: .medium))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
