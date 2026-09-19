import WidgetKit
import SwiftUI
import ProviderKit
import Preferences
import StatusUI

/// A timeline entry. The widget requests nothing itself: the app deposits the
/// data after every poll.
///
/// The whole reading rather than the snapshot inside it: "the app has not
/// written anything yet" and "the app wrote and this process may not read it"
/// are different things to say, and one of them is not about the accounts.
struct LimitsEntry: TimelineEntry {
    let date: Date
    let reading: SnapshotReading
}

struct LimitsProvider: TimelineProvider {
    func placeholder(in context: Context) -> LimitsEntry {
        LimitsEntry(date: Date(), reading: .nothingWritten)
    }

    func getSnapshot(in context: Context, completion: @escaping (LimitsEntry) -> Void) {
        completion(LimitsEntry(date: Date(), reading: SharedStore.reading()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LimitsEntry>) -> Void) {
        let entry = LimitsEntry(date: Date(), reading: SharedStore.reading())
        // Refreshed every five minutes: the countdowns change constantly while
        // the data itself arrives from the app as it polls. The system may defer
        // the refresh — which is exactly why the snapshot age is shown.
        let next = Date().addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

@main
struct SoftcapWidgetBundle: WidgetBundle {
    var body: some Widget { LimitsWidget() }
}

struct LimitsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.softcap.Softcap.limits", provider: LimitsProvider()) {
            LimitsWidgetView(entry: $0)
        }
        .configurationDisplayName("Subscription limits")
        .description("Remaining limits across your AI subscriptions.")
        // Every size: the user decides how many cells to give it.
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}
