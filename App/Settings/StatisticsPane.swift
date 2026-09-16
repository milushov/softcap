import SwiftUI
import Preferences
import Monitoring
import StatusUI

/// Usage over time: one chart, one line per account.
///
/// The history is recorded by the app as it polls, so the chart is as long as
/// the app has been running — it cannot show a week that was never watched. That
/// is said on screen rather than left for the reader to work out from a short
/// line.
struct StatisticsPane: View {
    @ObservedObject var model: PreferencesModel
    @ObservedObject var appModel: AppModel

    @ObservedObject private var loc = Localization.shared
    @State private var range: UsageRange = .week
    @State private var segments: [UsageSegment] = []
    @State private var accountIDs: [String] = []
    @State private var names: [String: String] = [:]
    @State private var now = Date()

    var body: some View {
        Pane(title: loc("Statistics"),
             subtitle: loc("How much of each weekly limit has been used, over time.")) {
            VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $range) {
                ForEach(UsageRange.allCases) { option in
                    Text(loc(option.titleKey)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)

            if segments.isEmpty {
                empty
            } else {
                UsageChart(
                    segments: segments, accountIDs: accountIDs, names: names,
                    range: range, now: now, localization: loc
                )
                .frame(height: 230)

                Text(loc(appModel.isDemo
                         ? "Demo — sample data"
                         : "A break in a line is a stretch with no readings taken, not a steady reading."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            }
        }
        .task(id: range) { await reload() }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc("Nothing recorded yet"))
                .font(.system(size: 12.5, weight: .semibold))
            Text(loc("Readings are kept as the app polls. Leave it running and the chart fills in."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 40)
    }

    private func reload() async {
        let history = await appModel.visibleHistory.current()
        let at = Date()
        let since = at.addingTimeInterval(-range.duration)
        now = at

        // Hiding an account stops it being polled, so its history simply ends.
        // Drawn unfiltered, the person's own choice arrives as a line that dies
        // mid-chart — which everywhere else here means the app was not running.
        let hidden = model.value.hiddenAccounts
        let drawn = Set(history.accountIDs(windowID: "weekly", since: since))
            .subtracting(hidden)

        segments = history.segments(windowID: "weekly", since: since, only: drawn)
        accountIDs = history.accountIDs(windowID: "weekly", since: since, only: drawn)

        // Names come from the credential store first, which holds them whether
        // or not the account answered this launch. Taking them from the live
        // snapshots alone left anything that had not polled nameless, and the
        // legend prints an id when it has no name — an account UUID, on screen.
        var found = Dictionary(
            uniqueKeysWithValues: await appModel.accountRows().map { ($0.id, $0.displayName) }
        )
        for snapshot in appModel.snapshots { found[snapshot.id] = snapshot.displayName }
        names = found
    }
}
