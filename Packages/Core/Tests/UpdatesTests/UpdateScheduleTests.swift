import Testing
import Foundation
@testable import Updates

@Suite struct WhenAcheckIsDue {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func hoursAgo(_ hours: Double) -> Date {
        now.addingTimeInterval(-hours * 3600)
    }

    @Test func nothingCheckedYetIsDue() {
        #expect(UpdateSchedule.isDue(lastChecked: nil, now: now))
    }

    @Test func acheckAnHourOldIsNotDue() {
        #expect(!UpdateSchedule.isDue(lastChecked: hoursAgo(1), now: now))
    }

    @Test func acheckAdayOldIsDue() {
        #expect(UpdateSchedule.isDue(lastChecked: hoursAgo(24), now: now))
        #expect(UpdateSchedule.isDue(lastChecked: hoursAgo(48), now: now))
    }

    @Test func theBoundaryIsTheDayItself() {
        #expect(!UpdateSchedule.isDue(lastChecked: hoursAgo(23.9), now: now))
        #expect(UpdateSchedule.isDue(lastChecked: hoursAgo(24.1), now: now))
    }

    /// A clock corrected backwards — a machine that woke with the wrong time and
    /// then found a time server — leaves the last check in the future. Measured
    /// as an interval that is a negative age, which is never a day, and the app
    /// would stop checking until the clock caught up with itself.
    @Test func acheckInTheFutureIsDueNow() {
        #expect(UpdateSchedule.isDue(lastChecked: now.addingTimeInterval(3600), now: now))
    }
}
