import Testing
import Foundation
@testable import ProviderKit

@Test func severityFollowsThresholds() {
    #expect(Severity(percent: 0) == .ok)
    #expect(Severity(percent: 49.9) == .ok)
    #expect(Severity(percent: 50) == .warning)
    #expect(Severity(percent: 74.9) == .warning)
    #expect(Severity(percent: 75) == .hot)
    #expect(Severity(percent: 89.9) == .hot)
    #expect(Severity(percent: 90) == .critical)
    #expect(Severity(percent: 100) == .critical)
}

@Test func peakPercentIsTheWorstWindow() {
    let snapshot = AccountSnapshot(
        id: "claude/abc", provider: .claude,
        displayName: "a@b.c", planLabel: "Max 20x",
        windows: [
            LimitWindow(id: "session", percent: 5, resetsAt: nil),
            LimitWindow(id: "weekly", percent: 23, resetsAt: nil),
        ],
        freshness: .live(Date(timeIntervalSince1970: 0)), failure: nil
    )
    #expect(snapshot.peakPercent == 23)
    #expect(snapshot.peakWindow?.id == "weekly")
}

@Test func peakOfEmptyWindowsIsZero() {
    let snapshot = AccountSnapshot(
        id: "codex/x", provider: .codex,
        displayName: "T", planLabel: "Plus",
        windows: [], freshness: .snapshot(Date(timeIntervalSince1970: 0)),
        failure: ProviderFailure(kind: .noData, diagnostic: "no data")
    )
    #expect(snapshot.peakPercent == 0)
    #expect(snapshot.peakWindow == nil)
}

@Test func freshnessExposesCaptureTime() {
    let moment = Date(timeIntervalSince1970: 1_787_867_253)
    #expect(Freshness.live(moment).capturedAt == moment)
    #expect(Freshness.snapshot(moment).capturedAt == moment)
    #expect(Freshness.live(moment).isStale == false)
    #expect(Freshness.snapshot(moment).isStale == true)
}
