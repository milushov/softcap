import Testing
import Foundation
@testable import Monitoring

/// `begin` is mutating, so its result is taken into a local before the macro
/// sees it — `#expect` cannot call a mutating member on the value it captures.
@Suite struct LettingOnePollRunAtATime {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func theFirstRunGoesAhead() {
        var gate = RefreshGate()
        #expect(gate.begin(at: start) != nil)
    }

    @Test func aSecondRunIsTurnedAwayWhileTheFirstIsGoing() {
        var gate = RefreshGate()
        _ = gate.begin(at: start)
        #expect(gate.begin(at: start.addingTimeInterval(1)) == nil)
    }

    @Test func afterOneFinishesTheNextGoesAhead() {
        var gate = RefreshGate()
        let run = gate.begin(at: start)
        gate.end(run!)
        #expect(gate.begin(at: start.addingTimeInterval(1)) != nil)
    }

    /// The defect this exists for: a poll that never returned held the flag for
    /// good, and every tick after it turned around at the door.
    @Test func aRunThatNeverFinishesStopsHoldingTheDoor() {
        var gate = RefreshGate(stallAfter: 90)
        _ = gate.begin(at: start)
        #expect(gate.begin(at: start.addingTimeInterval(89)) == nil,
                "gave up on the running poll too early")
        #expect(gate.begin(at: start.addingTimeInterval(91)) != nil,
                "still shut after the deadline")
    }

    @Test func displacingAStuckRunIsReportable() {
        var gate = RefreshGate(stallAfter: 90)
        _ = gate.begin(at: start)
        #expect(!gate.wouldDisplace(at: start.addingTimeInterval(10)))
        #expect(gate.wouldDisplace(at: start.addingTimeInterval(91)))
    }

    @Test func nothingToDisplaceWhenNothingIsRunning() {
        let gate = RefreshGate()
        #expect(!gate.wouldDisplace(at: start))
    }

    /// Displacing restarts the clock, so a second stuck run gets its own full
    /// deadline rather than being pushed aside at once.
    @Test func theDeadlineRestartsWithEachRun() {
        var gate = RefreshGate(stallAfter: 90)
        _ = gate.begin(at: start)
        _ = gate.begin(at: start.addingTimeInterval(91))
        #expect(gate.begin(at: start.addingTimeInterval(120)) == nil)
        #expect(gate.begin(at: start.addingTimeInterval(182)) != nil)
    }

    /// The stuck run is not killed — cancellation does not reach a blocking
    /// call — so it may still return long after something replaced it. Ending
    /// takes its own permit, so it cannot open the gate on the run that is still
    /// going: otherwise two polls would be in flight at once.
    @Test func aLateFinisherCannotReleaseSomebodyElsesRun() {
        var gate = RefreshGate(stallAfter: 90)
        let stuck = gate.begin(at: start)
        _ = gate.begin(at: start.addingTimeInterval(91))   // displaces it
        gate.end(stuck!)                                    // the stuck one, at last
        #expect(gate.begin(at: start.addingTimeInterval(92)) == nil,
                "the latecomer opened the gate on a poll that is still running")
    }

    @Test func theRunThatHoldsTheGateCanReleaseIt() {
        var gate = RefreshGate(stallAfter: 90)
        _ = gate.begin(at: start)
        let second = gate.begin(at: start.addingTimeInterval(91))
        gate.end(second!)
        #expect(gate.begin(at: start.addingTimeInterval(92)) != nil)
    }
}
