import WidgetKit
import SwiftUI
import ProviderKit
import Preferences
import StatusUI

/// A timeline entry. The widget fetches nothing itself: the phone app writes the
/// snapshot to the shared group container after each refresh.
struct PhoneEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedSnapshot?
}

struct PhoneProvider: TimelineProvider {
    func placeholder(in context: Context) -> PhoneEntry {
        PhoneEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PhoneEntry) -> Void) {
        completion(PhoneEntry(date: Date(), snapshot: SharedStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PhoneEntry>) -> Void) {
        let entry = PhoneEntry(date: Date(), snapshot: SharedStore.read())
        // Fifteen minutes rather than the Mac's five: iOS budgets widget
        // refreshes tightly, and asking too often only makes the system refuse.
        // The countdowns are recomputed on every render regardless.
        let next = Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

@main
struct PhoneWidgetBundle: WidgetBundle {
    var body: some Widget { PhoneLimitsWidget() }
}

struct PhoneLimitsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.softcap.Softcap.ios.limits",
                            provider: PhoneProvider()) {
            PhoneWidgetView(entry: $0)
        }
        .configurationDisplayName("Subscription limits")
        .description("Remaining limits across your AI subscriptions.")
        // Home screen and lock screen. The accessory families carry a single
        // number, which is all a lock screen has room for.
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular,
        ])
    }
}
