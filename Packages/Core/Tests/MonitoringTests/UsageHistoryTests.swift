import Testing
import Foundation
import ProviderKit
@testable import Monitoring

@Suite struct RecordingUsage {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func snap(
        _ id: String, session: Double? = nil, weekly: Double? = nil,
        failed: Bool = false
    ) -> AccountSnapshot {
        var windows: [LimitWindow] = []
        if let session { windows.append(LimitWindow(id: "session", percent: session, resetsAt: nil)) }
        if let weekly { windows.append(LimitWindow(id: "weekly", percent: weekly, resetsAt: nil)) }
        return AccountSnapshot(
            id: id, provider: .claude, displayName: id, planLabel: "Max",
            windows: windows, freshness: .live(start),
            failure: failed ? ProviderFailure(kind: .network, diagnostic: "d") : nil
        )
    }

    @Test func theFirstReadingIsAlwaysKept() {
        var history = UsageHistory()
        history.record([snap("a", weekly: 10)], at: start)
        #expect(history.samples.count == 1)
        #expect(history.samples.first?.percent == 10)
    }

    /// A poll runs as often as once a minute; keeping every one of them would
    /// fill the file with readings that say the same thing.
    @Test func aRepeatedReadingTooSoonIsDropped() {
        var history = UsageHistory()
        history.record([snap("a", weekly: 10)], at: start)
        history.record([snap("a", weekly: 10)], at: start.addingTimeInterval(60))
        history.record([snap("a", weekly: 10.2)], at: start.addingTimeInterval(120))
        #expect(history.samples.count == 1)
    }

    @Test func aChangedReadingIsKeptOnceTheSpacingHasPassed() {
        var history = UsageHistory()
        history.record([snap("a", weekly: 10)], at: start)
        history.record([snap("a", weekly: 25)], at: start.addingTimeInterval(6 * 60))
        #expect(history.samples.count == 2)
        #expect(history.samples.last?.percent == 25)
    }

    /// Without it a flat line and a stretch with no app running would look the
    /// same on the chart.
    @Test func anUnchangedReadingIsKeptAsAHeartbeat() {
        var history = UsageHistory()
        history.record([snap("a", weekly: 10)], at: start)
        history.record([snap("a", weekly: 10)], at: start.addingTimeInterval(10 * 60))
        #expect(history.samples.count == 1, "kept too early")
        history.record([snap("a", weekly: 10)], at: start.addingTimeInterval(31 * 60))
        #expect(history.samples.count == 2, "the heartbeat never fired")
    }

    /// A reset is the most informative point on the chart, and it is a drop.
    @Test func aResetToZeroIsRecorded() {
        var history = UsageHistory()
        history.record([snap("a", weekly: 95)], at: start)
        history.record([snap("a", weekly: 0)], at: start.addingTimeInterval(6 * 60))
        #expect(history.samples.map(\.percent) == [95, 0])
    }

    /// A failed account has no reading. Repeating the last one would put a
    /// measurement on the chart that was never taken.
    @Test func aFailedAccountIsNotRecorded() {
        var history = UsageHistory()
        history.record([snap("a", weekly: 10, failed: true)], at: start)
        #expect(history.samples.isEmpty)
    }

    @Test func everyWindowOfAnAccountIsRecorded() {
        var history = UsageHistory()
        history.record([snap("a", session: 40, weekly: 10)], at: start)
        #expect(Set(history.samples.map(\.windowID)) == ["session", "weekly"])
    }

    @Test func accountsAreKeptApart() {
        var history = UsageHistory()
        history.record([snap("a", weekly: 10), snap("b", weekly: 80)], at: start)
        #expect(history.samples.count == 2)
        #expect(Set(history.samples.map(\.accountID)) == ["a", "b"])
    }
}

@Suite struct ReadingUsageBack {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample(_ minutes: Double, _ account: String, _ percent: Double) -> UsageSample {
        UsageSample(at: start.addingTimeInterval(minutes * 60),
                    accountID: account, windowID: "weekly", percent: percent)
    }

    /// The point of segmenting: the app is not always running, and a line drawn
    /// across the hours it was asleep claims a figure nobody measured.
    @Test func aQuietSpellBreaksTheLine() {
        let history = UsageHistory(samples: [
            sample(0, "a", 10), sample(30, "a", 20),
            sample(600, "a", 50), sample(630, "a", 60),   // ten hours later
        ])
        let segments = history.segments(windowID: "weekly", since: start.addingTimeInterval(-60))
        #expect(segments.count == 2, "the gap was drawn through")
        #expect(segments.first?.points.count == 2)
        #expect(segments.last?.points.count == 2)
    }

    @Test func acontinuousRunStaysOneSegment() {
        let history = UsageHistory(samples: [
            sample(0, "a", 10), sample(30, "a", 20), sample(60, "a", 30),
        ])
        let segments = history.segments(windowID: "weekly", since: start.addingTimeInterval(-60))
        #expect(segments.count == 1)
        #expect(segments.first?.points.count == 3)
    }

    @Test func eachAccountGetsItsOwnSegments() {
        let history = UsageHistory(samples: [
            sample(0, "a", 10), sample(0, "b", 80), sample(30, "a", 20), sample(30, "b", 85),
        ])
        let segments = history.segments(windowID: "weekly", since: start.addingTimeInterval(-60))
        #expect(segments.count == 2)
        #expect(Set(segments.map(\.accountID)) == ["a", "b"])
    }

    @Test func onlyTheAskedForWindowComesBack() {
        let history = UsageHistory(samples: [
            sample(0, "a", 10),
            UsageSample(at: start, accountID: "a", windowID: "session", percent: 99),
        ])
        let segments = history.segments(windowID: "weekly", since: start.addingTimeInterval(-60))
        #expect(segments.flatMap(\.points).allSatisfy { $0.windowID == "weekly" })
        #expect(segments.flatMap(\.points).count == 1)
    }

    @Test func readingsBeforeTheRangeAreLeftOut() {
        let history = UsageHistory(samples: [sample(0, "a", 10), sample(120, "a", 20)])
        let segments = history.segments(windowID: "weekly", since: start.addingTimeInterval(60 * 60))
        #expect(segments.flatMap(\.points).count == 1)
    }

    /// A colour that moved between redraws would be worse than no colour.
    @Test func accountOrderIsStable() {
        let history = UsageHistory(samples: [sample(0, "b", 1), sample(1, "a", 1), sample(2, "c", 1)])
        let ids = history.accountIDs(windowID: "weekly", since: start.addingTimeInterval(-60))
        #expect(ids == ["a", "b", "c"])
    }

    @Test func pruningDropsWhatIsTooOld() {
        var history = UsageHistory(samples: [sample(0, "a", 10), sample(60 * 24 * 40, "a", 20)])
        history.prune(before: start.addingTimeInterval(60 * 60))
        #expect(history.samples.count == 1)
        #expect(history.samples.first?.percent == 20)
    }

    /// Codex keeps its own history in session files, so importing runs more than
    /// once and must not multiply the readings.
    @Test func mergingTheSameReadingsTwiceChangesNothing() {
        var history = UsageHistory()
        let incoming = [sample(0, "a", 10), sample(30, "a", 20)]
        history.merge(incoming)
        history.merge(incoming)
        #expect(history.samples.count == 2)
    }

    @Test func mergedReadingsLandInTimeOrder() {
        var history = UsageHistory(samples: [sample(60, "a", 30)])
        history.merge([sample(0, "a", 10)])
        #expect(history.samples.map(\.percent) == [10, 30])
    }

    @Test func survivesEncodingAsJSON() throws {
        let history = UsageHistory(samples: [sample(0, "a", 10), sample(30, "b", 20)])
        let data = try JSONEncoder().encode(history)
        let back = try JSONDecoder().decode(UsageHistory.self, from: data)
        #expect(back == history)
    }
}

/// Imported readings arrive at whatever rate their source wrote them — Codex
/// logs one on every turn — and a history holding two densities would make any
/// statement about how much it keeps true of only half the file.
@Suite struct ThinningImportedReadings {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample(_ seconds: Double, _ percent: Double, _ window: String = "weekly") -> UsageSample {
        UsageSample(at: start.addingTimeInterval(seconds),
                    accountID: "codex/a", windowID: window, percent: percent)
    }

    @Test func aBurstOfReadingsCollapses() {
        // Two minutes apart, as Codex writes them.
        let dense = (0..<30).map { sample(Double($0) * 120, Double($0)) }
        let thin = UsageHistory.thinned(dense)
        #expect(thin.count < dense.count / 2, "kept \(thin.count) of \(dense.count)")
        #expect(thin.first == dense.first, "the run must start where it started")
    }

    @Test func widelySpacedReadingsAreAllKept() {
        let sparse = (0..<5).map { sample(Double($0) * 600, Double($0) * 10) }
        #expect(UsageHistory.thinned(sparse).count == 5)
    }

    /// Thinning must not merge accounts or windows into one another.
    @Test func windowsAreThinnedApart() {
        let mixed = [
            sample(0, 10, "weekly"), sample(0, 90, "session"),
            sample(600, 20, "weekly"), sample(600, 95, "session"),
        ]
        let thin = UsageHistory.thinned(mixed)
        #expect(thin.filter { $0.windowID == "weekly" }.count == 2)
        #expect(thin.filter { $0.windowID == "session" }.count == 2)
    }

    /// Importing runs on every launch, so the same files must yield the same
    /// readings — otherwise each launch would add a slightly different subset.
    @Test func thinningTheSameInputTwiceGivesTheSameResult() {
        let dense = (0..<40).map { sample(Double($0) * 90, Double($0) * 2) }
        #expect(UsageHistory.thinned(dense) == UsageHistory.thinned(dense))
    }

    @Test func repeatedImportsDoNotMultiply() {
        let dense = (0..<40).map { sample(Double($0) * 90, Double($0) * 2) }
        var history = UsageHistory()
        history.merge(UsageHistory.thinned(dense))
        let after = history.samples.count
        history.merge(UsageHistory.thinned(dense))
        #expect(history.samples.count == after)
    }

    @Test func unsortedInputIsHandled() {
        let shuffled = [sample(600, 20), sample(0, 10), sample(1200, 30)]
        let thin = UsageHistory.thinned(shuffled)
        #expect(thin.map(\.percent) == [10, 20, 30])
    }
}

/// The Codex import announced "imported 73 codex readings" on every launch,
/// having added none of them since the first: it reported how many it offered.
/// A count nobody could check, in a line written to be checked.
@Suite struct MergeSaysHowManyWereNew {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func samples(_ minutes: [Double]) -> [UsageSample] {
        minutes.map {
            UsageSample(at: start.addingTimeInterval($0 * 60),
                        accountID: "a", windowID: "weekly", percent: 50)
        }
    }

    @Test func everythingNewIsCounted() {
        var history = UsageHistory()
        #expect(history.merge(samples([0, 5, 10])) == 3)
    }

    @Test func theSecondMergeOfTheSameReadingsAddsNothing() {
        var history = UsageHistory()
        _ = history.merge(samples([0, 5, 10]))
        #expect(history.merge(samples([0, 5, 10])) == 0,
                "the readings were already there; saying three would be the old bug")
    }

    @Test func onlyTheUnseenOnesCount() {
        var history = UsageHistory()
        _ = history.merge(samples([0, 5]))
        #expect(history.merge(samples([0, 5, 10, 15])) == 2)
    }

    @Test func mergingNothingCountsNothing() {
        var history = UsageHistory()
        #expect(history.merge([]) == 0)
    }
}
