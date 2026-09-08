import Testing
import Foundation
import ProviderKit
@testable import StatusUI
@testable import Monitoring

/// The chart is drawn from history, and history outlives the accounts in it.
@Suite struct TheChartDrawsWhatItCanName {

    /// An account can be in the history and absent from the answers: hidden,
    /// forgotten, or not polled yet this launch. The legend printed the id.
    @Test func anUnknownAccountIsNamedByItsService() {
        let names = ["claude/aaa": "sam@example.com"]
        #expect(LegendNames.label(for: "claude/aaa", in: names) == "sam@example.com")
        #expect(LegendNames.label(for: "claude/bbb", in: names) == "Claude")
        #expect(LegendNames.label(for: "codex/ccc", in: names) == "Codex")
    }

    @Test func nothingInTheLegendLooksLikeAnIdentifier() {
        let ids = ["claude/9f3e1a2b-4c5d-6e7f", "codex/f2338a14", "claude/known"]
        for id in ids {
            let label = LegendNames.label(for: id, in: ["claude/known": "sam@example.com"])
            #expect(!label.contains("/"), "the legend shows the identifier \(label)")
        }
    }

    /// Hiding an account stops it being polled, so its line would simply stop —
    /// and a stopped line means, everywhere else in this chart, that nothing was
    /// measured. The person's own choice would arrive as an outage.
    @Test func ahiddenAccountIsNotDrawnAtAll() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var history = UsageHistory()
        func account(_ id: String, _ percent: Double) -> AccountSnapshot {
            AccountSnapshot(
                id: id, provider: .claude, displayName: id, planLabel: "Max 20x",
                windows: [LimitWindow(id: "weekly", percent: percent, resetsAt: nil)],
                freshness: .live(start), failure: nil
            )
        }
        for minute in stride(from: 0, to: 120, by: 30) {
            let at = start.addingTimeInterval(Double(minute) * 60)
            history.record(
                [account("claude/kept", 10 + Double(minute)),
                 account("claude/hidden", 20 + Double(minute))],
                at: at
            )
        }
        let since = start.addingTimeInterval(-60)

        #expect(history.accountIDs(windowID: "weekly", since: since).count == 2)

        let drawn: Set<String> = ["claude/kept"]
        #expect(history.accountIDs(windowID: "weekly", since: since, only: drawn) == ["claude/kept"])
        let segments = history.segments(windowID: "weekly", since: since, only: drawn)
        #expect(segments.allSatisfy { $0.accountID == "claude/kept" })
        #expect(!segments.isEmpty, "filtering must not empty the chart")
    }
}
