import Testing
import Foundation
@testable import Monitoring

@Suite struct HowOldTheReadingIs {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let interval: TimeInterval = 300      // the background poll

    private func age(_ secondsAgo: TimeInterval) -> ReadingAge {
        readingAge(lastUpdated: now.addingTimeInterval(-secondsAgo),
                   now: now, pollingEvery: interval)
    }

    @Test func afreshReadingIsCurrent() {
        #expect(age(10) == .current)
    }

    /// One missed poll is a hiccup — a slow network, a machine waking up.
    @Test func oneMissedPollIsNotYetAFault() {
        #expect(age(interval * 1.5) == .current)
        #expect(age(interval * 2.9) == .current)
    }

    @Test func threeMissedPollsAreAFault() {
        #expect(age(interval * 3.1).isOverdue)
    }

    @Test func theAgeComesBackWithTheVerdict() {
        guard case .overdue(let seconds) = age(3600) else {
            Issue.record("an hour-old reading was called current"); return
        }
        #expect(abs(seconds - 3600) < 1)
    }

    /// Nothing has been read yet — that is the empty window, not a stale one,
    /// and it has its own message.
    @Test func noReadingAtAllIsNotOverdue() {
        #expect(readingAge(lastUpdated: nil, now: now, pollingEvery: interval) == .current)
    }

    /// The window polls once a minute while it is open, but a reading taken
    /// while it was shut is five minutes apart by design and must not be called
    /// stale for it.
    @Test func theSlowestCadenceIsWhatCounts() {
        let openInterval: TimeInterval = 60
        #expect(readingAge(lastUpdated: now.addingTimeInterval(-240),
                           now: now, pollingEvery: interval) == .current)
        #expect(readingAge(lastUpdated: now.addingTimeInterval(-240),
                           now: now, pollingEvery: openInterval).isOverdue,
                "against the open-window cadence four minutes would be overdue")
    }

    @Test func theToleranceIsAdjustable() {
        #expect(readingAge(lastUpdated: now.addingTimeInterval(-400),
                           now: now, pollingEvery: interval, tolerating: 1).isOverdue)
    }
}
