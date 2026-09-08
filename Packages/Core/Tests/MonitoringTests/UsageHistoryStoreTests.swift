import Testing
import Foundation
@testable import Monitoring
import ProviderKit

/// The store is what runs: it reads and writes the file, thins on the way in,
/// and decides when not to write at all. It had no tests.
///
/// `UsageHistory` is covered — but every one of those tests exercises the value
/// type. Take the `prune` line out of `UsageHistoryStore.record` and all of them
/// still pass, while the file on disk grows for ever.
///
/// Written now because the retention is about to matter for the first time: the
/// history on this machine spans thirty-four days against a thirty-five day
/// ceiling, so the oldest reading is a day from being dropped by a path that has
/// never run.
@Suite struct TheHistoryStoreOnDisk {

    private static func file() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("softcap-history-\(UUID().uuidString).json")
    }

    private static func snapshot(_ percent: Double) -> AccountSnapshot {
        AccountSnapshot(
            id: "claude/a", provider: .claude, displayName: "a", planLabel: "Max 20x",
            windows: [LimitWindow(id: "weekly", percent: percent, resetsAt: nil)],
            freshness: .live(Date()), failure: nil
        )
    }

    @Test func recordingDropsWhatHasAgedOut() async throws {
        let url = Self.file()
        let store = UsageHistoryStore(url: url)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = now.addingTimeInterval(-UsageHistory.retention - 3600)

        await store.record([Self.snapshot(10)], at: old)
        #expect(await store.current().samples.count == 1)

        // A second reading, a retention later. The first is now too old.
        await store.record([Self.snapshot(20)], at: now)
        let kept = await store.current().samples
        #expect(kept.count == 1, "the aged reading was not dropped")
        #expect(kept.first?.percent == 20)
    }

    /// `removeAll { $0.at < cutoff }` keeps a reading that sits exactly on the
    /// line. Stated here because it is the kind of thing a rewrite flips without
    /// meaning to, and because a month of history hangs off the comparison.
    @Test func aReadingExactlyOnTheCutoffIsKept() {
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        var history = UsageHistory(samples: [
            UsageSample(at: at, accountID: "a", windowID: "weekly", percent: 5)
        ])
        history.prune(before: at)
        #expect(history.samples.count == 1)
    }

    /// A poll that adds nothing must not rewrite the file. The app polls as often
    /// as once a minute and the thinning rule rejects most of those; writing
    /// anyway would rewrite a month of readings all day for nothing.
    @Test func aPollThatChangesNothingLeavesTheFileAlone() async throws {
        let url = Self.file()
        let store = UsageHistoryStore(url: url)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        await store.record([Self.snapshot(10)], at: now)
        let first = try FileManager.default.attributesOfItem(atPath: url.path)
        let firstSize = first[.size] as? Int

        // Same figure a minute later: inside the five-minute spacing, so nothing
        // is kept and nothing should be written.
        await store.record([Self.snapshot(10)], at: now.addingTimeInterval(60))
        #expect(await store.current().samples.count == 1)

        let second = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect(second[.size] as? Int == firstSize)
        #expect(
            (first[.modificationDate] as? Date) == (second[.modificationDate] as? Date),
            "the file was rewritten for a poll that added nothing"
        )
    }

    @Test func whatWasWrittenComesBack() async throws {
        let url = Self.file()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let writer = UsageHistoryStore(url: url)
        await writer.record([Self.snapshot(42)], at: now)

        let reader = UsageHistoryStore(url: url)
        await reader.load()
        let samples = await reader.current().samples
        #expect(samples.count == 1)
        #expect(samples.first?.percent == 42)
    }
}

/// One unreadable reading must not cost the month.
@Suite struct AHistoryWithOneBadReading {

    private func file() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("softcap-bad-\(UUID().uuidString).json")
    }

    @Test func theOthersSurvive() async throws {
        // Three readings, the middle one missing a field a later build might add
        // or an interrupted write might have lost.
        let json = """
        {"samples":[
          {"at":700000000,"accountID":"claude/a","windowID":"weekly","percent":10},
          {"at":700000060,"accountID":"claude/a","windowID":"weekly"},
          {"at":700000120,"accountID":"claude/a","windowID":"weekly","percent":30}
        ]}
        """
        let url = file()
        try Data(json.utf8).write(to: url)

        let store = UsageHistoryStore(url: url)
        await store.load()
        let samples = await store.current().samples
        #expect(samples.count == 2, "a single malformed reading took the others with it")
        #expect(samples.map(\.percent) == [10, 30])
    }

    /// And a file that is not a history at all still yields an empty one rather
    /// than a crash.
    @Test func rubbishIsAnEmptyHistory() async throws {
        let url = file()
        try Data("not a history".utf8).write(to: url)
        let store = UsageHistoryStore(url: url)
        await store.load()
        #expect(await store.current().samples.isEmpty)
    }
}
