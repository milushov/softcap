import Testing
import Foundation
@testable import Monitoring
import ProviderKit

/// Which account a person is working with, guessed from the readings.
///
/// The app is not allowed to ask the CLI — see the decision of 2026-09-14,
/// "Softcap opens one keychain item, and it is its own" — so the answer comes
/// out of the polls that were happening anyway. This suite holds the rule that
/// turns a series of percentages into a name.
@Suite struct TheAccountInUse {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func account(
        _ id: String, session: Double? = nil, weekly: Double? = nil, failed: Bool = false
    ) -> AccountSnapshot {
        var windows: [LimitWindow] = []
        if let session { windows.append(LimitWindow(id: "session", percent: session, resetsAt: nil)) }
        if let weekly { windows.append(LimitWindow(id: "weekly", percent: weekly, resetsAt: nil)) }
        return AccountSnapshot(
            id: id, provider: .claude, displayName: id, planLabel: "Max",
            windows: windows, freshness: .live(start),
            failure: failed ? ProviderFailure(kind: .network) : nil
        )
    }

    @Test func theFirstPollNamesNobody() {
        var tracker = ActiveAccountTracker()
        tracker.observe([account("a", session: 10), account("b", session: 80)], at: start)
        // Everything is a rise from nothing on the first sight of it, so the
        // biggest number would win and the answer would be "whoever is fullest"
        // wearing this feature's name.
        #expect(tracker.accountInUse == nil)
    }

    @Test func theAccountThatRoseIsTheOneInUse() {
        var tracker = ActiveAccountTracker()
        tracker.observe([account("a", session: 10), account("b", session: 80)], at: start)
        tracker.observe([account("a", session: 14), account("b", session: 80)],
                        at: start.addingTimeInterval(60))
        #expect(tracker.accountInUse == "a")
    }

    @Test func aFallIsAResetAndNotActivity() {
        var tracker = ActiveAccountTracker()
        tracker.observe([account("a", session: 10), account("b", session: 80)], at: start)
        tracker.observe([account("a", session: 14), account("b", session: 80)],
                        at: start.addingTimeInterval(60))
        // b's window resets. That is the clock, not a person.
        tracker.observe([account("a", session: 14), account("b", session: 0)],
                        at: start.addingTimeInterval(120))
        #expect(tracker.accountInUse == "a")
    }

    @Test func risingAgainAfterAResetCounts() {
        var tracker = ActiveAccountTracker()
        tracker.observe([account("b", session: 80)], at: start)
        tracker.observe([account("b", session: 0)], at: start.addingTimeInterval(60))
        tracker.observe([account("b", session: 3)], at: start.addingTimeInterval(120))
        #expect(tracker.accountInUse == "b")
    }

    @Test func theLargerRiseSettlesOnePoll() {
        var tracker = ActiveAccountTracker()
        tracker.observe([account("a", session: 10), account("b", session: 10)], at: start)
        tracker.observe([account("a", session: 11), account("b", session: 15)],
                        at: start.addingTimeInterval(60))
        #expect(tracker.accountInUse == "b")
    }

    @Test func theMoreRecentRiseOutranksTheLargerOne() {
        var tracker = ActiveAccountTracker()
        tracker.observe([account("a", session: 10), account("b", session: 10)], at: start)
        tracker.observe([account("a", session: 10), account("b", session: 40)],
                        at: start.addingTimeInterval(60))
        tracker.observe([account("a", session: 11), account("b", session: 40)],
                        at: start.addingTimeInterval(120))
        #expect(tracker.accountInUse == "a")
    }

    @Test func theAnswerHoldsWhileNothingMoves() {
        var tracker = ActiveAccountTracker()
        tracker.observe([account("a", session: 10), account("b", session: 80)], at: start)
        tracker.observe([account("a", session: 14), account("b", session: 80)],
                        at: start.addingTimeInterval(60))
        for minute in 2...120 {
            tracker.observe([account("a", session: 14), account("b", session: 80)],
                            at: start.addingTimeInterval(Double(minute) * 60))
        }
        // Two hours away from the desk does not change which account you come
        // back to.
        #expect(tracker.accountInUse == "a")
    }

    @Test func aFailedReadingIsSkippedAndCostsNothing() {
        var tracker = ActiveAccountTracker()
        tracker.observe([account("a", session: 10), account("b", session: 80)], at: start)
        tracker.observe([account("a", session: 14), account("b", session: 80)],
                        at: start.addingTimeInterval(60))
        tracker.observe([account("a", failed: true), account("b", session: 80)],
                        at: start.addingTimeInterval(120))
        #expect(tracker.accountInUse == "a")
        // And the mark survives the outage: coming back at the same percentage
        // is not a rise.
        tracker.observe([account("a", session: 14), account("b", session: 80)],
                        at: start.addingTimeInterval(180))
        #expect(tracker.accountInUse == "a")
    }

    @Test func noiseBelowTheFloorIsNotARise() {
        var tracker = ActiveAccountTracker()
        tracker.observe([account("a", session: 10), account("b", session: 80)], at: start)
        tracker.observe([account("a", session: 10.001), account("b", session: 80)],
                        at: start.addingTimeInterval(60))
        #expect(tracker.accountInUse == nil)
    }

    @Test func theLargestWindowOfAnAccountIsItsRise() {
        var tracker = ActiveAccountTracker()
        tracker.observe([account("a", session: 10, weekly: 40),
                         account("b", session: 10, weekly: 40)], at: start)
        // a moves its weekly by 5, b moves its session by 2. a did more.
        tracker.observe([account("a", session: 10, weekly: 45),
                         account("b", session: 12, weekly: 40)],
                        at: start.addingTimeInterval(60))
        #expect(tracker.accountInUse == "a")
    }

    @Test func anAccountSeenForTheFirstTimeMidRunDoesNotWin() {
        var tracker = ActiveAccountTracker()
        tracker.observe([account("a", session: 10)], at: start)
        tracker.observe([account("a", session: 14)], at: start.addingTimeInterval(60))
        // A second account signs in and arrives at 90% of its weekly. Nothing
        // about that is something that just happened.
        tracker.observe([account("a", session: 14), account("b", session: 90)],
                        at: start.addingTimeInterval(120))
        #expect(tracker.accountInUse == "a")
    }
}
