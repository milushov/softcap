import WidgetKit
import SwiftUI
import ProviderKit
import Preferences
import StatusUI

/// A timeline entry. The widget requests nothing itself: the app deposits the
/// data after every poll.
struct LimitsEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedSnapshot?
}

struct LimitsProvider: TimelineProvider {
    func placeholder(in context: Context) -> LimitsEntry {
        LimitsEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (LimitsEntry) -> Void) {
        completion(LimitsEntry(date: Date(), snapshot: SharedStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LimitsEntry>) -> Void) {
        let entry = LimitsEntry(date: Date(), snapshot: SharedStore.read())
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
