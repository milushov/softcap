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

/// The daily rhythm answers "is it time to look again on our own". It does not
/// answer "somebody opened the screen that shows the answer, and the answer is
/// from this morning" — and for seven releases in one day, that was the same
/// screen confidently offering the first of them.
@Suite struct WhenAnAnswerOnScreenIsOld {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func minutesAgo(_ minutes: Double) -> Date {
        now.addingTimeInterval(-minutes * 60)
    }

    @Test func nothingCheckedYetIsStale() {
        #expect(UpdateSchedule.isStale(lastChecked: nil, now: now))
    }

    @Test func anAnswerAMinuteOldIsFresh() {
        #expect(!UpdateSchedule.isStale(lastChecked: minutesAgo(1), now: now))
    }

    @Test func anAnswerAnHourOldIsStale() {
        #expect(UpdateSchedule.isStale(lastChecked: minutesAgo(60), now: now))
    }

    /// The five minutes themselves, and not only either side of them.
    ///
    /// 4.9 and 5.1 read the same under `>` as under `>=`, so the pair alone left
    /// the comparison free to be either — a mutant that only asks again after
    /// five minutes have been *passed* survived the whole suite. The moment is
    /// exactly 300 seconds: `minutesAgo(5)` of a whole-number epoch has no
    /// remainder to round.
    @Test func theBoundaryIsTheFiveMinutesItself() {
        #expect(!UpdateSchedule.isStale(lastChecked: minutesAgo(4.9), now: now))
        #expect(UpdateSchedule.isStale(lastChecked: minutesAgo(5), now: now))
        #expect(UpdateSchedule.isStale(lastChecked: minutesAgo(5.1), now: now))
    }

    /// The same clock correction the daily check guards against, for the same
    /// reason: a negative age is never five minutes either.
    @Test func anAnswerFromTheFutureIsStaleNow() {
        #expect(UpdateSchedule.isStale(lastChecked: now.addingTimeInterval(3600), now: now))
    }

    /// The point of the second interval. Were it the longer of the two, opening
    /// the screen would ask less often than the app asks by itself, and the
    /// stale offer this was written for would still be on screen.
    @Test func openingTheScreenAsksSoonerThanTheDailyCheck() {
        #expect(UpdateSchedule.staleAfter < UpdateSchedule.interval)
    }
}
