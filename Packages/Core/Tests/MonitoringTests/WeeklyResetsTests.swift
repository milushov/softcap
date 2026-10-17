import Testing
import Foundation
@testable import Monitoring

@Suite struct PastWeeklyResetsAreProjected {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    @Test func aWeekOfHistoryHoldsOneResetWhenTheNextIsThreeDaysAway() {
        let next = now.addingTimeInterval(3 * day)
        let found = WeeklyResets.resets(
            known: next, from: now.addingTimeInterval(-7 * day), to: now)
        // next - 7d is 4 days before now: inside; next itself is in the future.
        #expect(found == [next.addingTimeInterval(-7 * day)])
    }

    @Test func aMonthHoldsFourOrFiveOfThem() {
        let next = now.addingTimeInterval(1 * day)
        let found = WeeklyResets.resets(
            known: next, from: now.addingTimeInterval(-30 * day), to: now)
        #expect(found.count == 4)
        #expect(found == found.sorted())
        #expect(found.last == next.addingTimeInterval(-7 * day))
    }

    @Test func theFutureIsNeverReturned() {
        let next = now.addingTimeInterval(2 * day)
        let found = WeeklyResets.resets(
            known: next, from: now.addingTimeInterval(-30 * day), to: now)
        #expect(found.allSatisfy { $0 <= now })
    }

    @Test func aResetOnTheEdgeIsKept() {
        let start = now.addingTimeInterval(-7 * day)
        let found = WeeklyResets.resets(known: now, from: start, to: now)
        #expect(found == [start, now])
    }

    @Test func aKnownResetInThePastWorksToo() {
        let known = now.addingTimeInterval(-20 * day)
        let found = WeeklyResets.resets(
            known: known, from: now.addingTimeInterval(-30 * day), to: now)
        #expect(found == [-27, -20, -13, -6].map { now.addingTimeInterval(Double($0) * day) })
    }

    @Test func anEmptyOrBackwardsRangeIsEmpty() {
        #expect(WeeklyResets.resets(known: now, from: now, to: now.addingTimeInterval(-1)).isEmpty)
    }
}
