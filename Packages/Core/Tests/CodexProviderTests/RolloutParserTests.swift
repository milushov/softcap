import Testing
import Foundation
import ProviderKit
@testable import CodexProvider

private let eventLine = """
{"timestamp":"2026-08-27T16:47:37.701Z","ordinal":12,"type":"event_msg","payload":\
{"type":"token_count","info":{"model_context_window":258400},"rate_limits":\
{"limit_id":"codex","plan_type":"plus",\
"primary":{"used_percent":12.5,"window_minutes":300,"resets_at":1787867253},\
"secondary":{"used_percent":32.0,"window_minutes":10080,"resets_at":1788454053}}}}
"""

private let olderLine = """
{"timestamp":"2026-08-27T15:00:00.000Z","ordinal":4,"type":"event_msg","payload":\
{"type":"token_count","rate_limits":\
{"limit_id":"codex","plan_type":"plus",\
"primary":{"used_percent":1.0,"window_minutes":300,"resets_at":1787867253},\
"secondary":{"used_percent":2.0,"window_minutes":10080,"resets_at":1788454053}}}}
"""

private let noiseLine = """
{"timestamp":"2026-08-27T15:30:00.000Z","type":"event_msg","payload":{"type":"agent_message","message":"hello"}}
"""

@Test func readsPercentsAndWindows() throws {
    let event = try RolloutParser.latestEvent(inLines: [eventLine])
    #expect(event.planType == "plus")
    #expect(event.windows.count == 2)

    let session = try #require(event.windows.first { $0.id == "session" })
    #expect(session.percent == 12.5)
    #expect(session.resetsAt == Date(timeIntervalSince1970: 1_787_867_253))

    let weekly = try #require(event.windows.first { $0.id == "weekly" })
    #expect(weekly.percent == 32.0)
}

@Test func usesEventTimestampAsCaptureTime() throws {
    let event = try RolloutParser.latestEvent(inLines: [eventLine])
    #expect(event.capturedAt == CodexTimestamp.date(from: "2026-08-27T16:47:37.701Z"))
}

@Test func takesTheLastEventNotTheFirst() throws {
    let event = try RolloutParser.latestEvent(inLines: [olderLine, noiseLine, eventLine])
    #expect(event.windows.first { $0.id == "weekly" }?.percent == 32.0)
}

@Test func ignoresLinesWithoutRateLimits() throws {
    let event = try RolloutParser.latestEvent(inLines: [noiseLine, eventLine])
    #expect(event.windows.count == 2)
}

@Test func failsWithNoDataWhenNothingMatches() {
    #expect(throws: ProviderFailure.self) {
        try RolloutParser.latestEvent(inLines: [noiseLine])
    }
}

@Test func survivesBrokenJSONLine() throws {
    let event = try RolloutParser.latestEvent(inLines: ["{this is not json", eventLine])
    #expect(event.windows.count == 2)
}

@Test func omitsWindowThatServerReportsAsNull() throws {
    let onlyPrimary = """
    {"timestamp":"2026-08-27T16:00:00.000Z","type":"event_msg","payload":\
    {"type":"token_count","rate_limits":{"limit_id":"codex","plan_type":"pro",\
    "primary":{"used_percent":7.0,"window_minutes":300,"resets_at":1787867253},\
    "secondary":null}}}
    """
    let event = try RolloutParser.latestEvent(inLines: [onlyPrimary])
    #expect(event.windows.count == 1)
    #expect(event.windows[0].id == "session")
    #expect(event.planType == "pro")
}

/// Codex writes a reading every time it works, so a session file is a record of
/// how the limit moved — history this app never watched.
@Suite struct AllRateLimitEvents {

    private func line(_ stamp: String, primary: Double, secondary: Double) -> String {
        """
        {"timestamp":"\(stamp)","type":"event_msg","payload":{"type":"token_count",\
        "rate_limits":{"limit_id":"codex","plan_type":"plus",\
        "primary":{"used_percent":\(primary),"window_minutes":300,"resets_at":1787867253},\
        "secondary":{"used_percent":\(secondary),"window_minutes":10080,"resets_at":1788454053}}}}
        """
    }

    @Test func everyEventComesBackInOrder() {
        let events = RolloutParser.allEvents(inLines: [
            line("2026-08-27T10:00:00.000Z", primary: 10, secondary: 5),
            line("2026-08-27T12:00:00.000Z", primary: 40, secondary: 9),
            line("2026-08-27T14:00:00.000Z", primary: 70, secondary: 14),
        ])
        #expect(events.count == 3)
        #expect(events.map { $0.windows.first { $0.id == "session" }?.percent } == [10, 40, 70])
    }

    @Test func linesWithoutAReadingAreSkipped() {
        let events = RolloutParser.allEvents(inLines: [
            #"{"timestamp":"2026-08-27T10:00:00.000Z","payload":{"type":"agent_message"}}"#,
            line("2026-08-27T12:00:00.000Z", primary: 40, secondary: 9),
            "{not json at all",
        ])
        #expect(events.count == 1)
    }

    @Test func anEmptyFileYieldsNothing() {
        #expect(RolloutParser.allEvents(inLines: []).isEmpty)
    }

    /// `latestEvent` must keep answering with the last one; the two share their
    /// parsing now and could have drifted.
    @Test func theLastOfAllEventsIsTheLatestEvent() throws {
        let lines = [
            line("2026-08-27T10:00:00.000Z", primary: 10, secondary: 5),
            line("2026-08-27T14:00:00.000Z", primary: 70, secondary: 14),
        ]
        let all = RolloutParser.allEvents(inLines: lines)
        let latest = try RolloutParser.latestEvent(inLines: lines)
        #expect(all.last == latest)
    }
}

@Suite struct ImportingCodexHistory {

    private func line(_ stamp: String, primary: Double, secondary: Double) -> String {
        """
        {"timestamp":"\(stamp)","type":"event_msg","payload":{"type":"token_count",\
        "rate_limits":{"limit_id":"codex","plan_type":"plus",\
        "primary":{"used_percent":\(primary),"window_minutes":300,"resets_at":1787867253},\
        "secondary":{"used_percent":\(secondary),"window_minutes":10080,"resets_at":1788454053}}}}
        """
    }

    @Test func bothWindowsOfEveryEventBecomeSamples() {
        let samples = CodexHistoryImporter.samples(
            fromFiles: [[line("2026-08-27T10:00:00.000Z", primary: 10, secondary: 5)]],
            accountID: "codex/abc")
        #expect(samples.count == 2)
        #expect(Set(samples.map(\.windowID)) == ["session", "weekly"])
        #expect(samples.allSatisfy { $0.accountID == "codex/abc" })
    }

    @Test func filesAreGatheredIntoOneRunInTimeOrder() {
        let samples = CodexHistoryImporter.samples(fromFiles: [
            [line("2026-08-27T14:00:00.000Z", primary: 70, secondary: 14)],
            [line("2026-08-27T10:00:00.000Z", primary: 10, secondary: 5)],
        ], accountID: "codex/abc")
        let sessions = samples.filter { $0.windowID == "session" }
        #expect(sessions.map(\.percent) == [10, 70], "out of order")
    }

    /// A line whose timestamp will not parse yields the epoch, and one such
    /// sample would stretch the chart's axis back to 1970.
    @Test func readingsWithNoUsableTimeAreLeftOut() {
        let broken = """
        {"timestamp":"not-a-date","payload":{"type":"token_count",\
        "rate_limits":{"limit_id":"codex","plan_type":"plus",\
        "primary":{"used_percent":10,"window_minutes":300,"resets_at":1}}}}
        """
        let samples = CodexHistoryImporter.samples(fromFiles: [[broken]], accountID: "codex/abc")
        #expect(samples.isEmpty)
    }

    @Test func noFilesYieldNoSamples() {
        #expect(CodexHistoryImporter.samples(fromFiles: [], accountID: "codex/abc").isEmpty)
    }
}

/// Codex does not keep the five-hour window in `primary`. Some events carry the
/// weekly one there — `window_minutes: 10080` — with `secondary` null, and
/// reading the slot rather than the length filed those under "5h": a weekly
/// figure shown as a five-hour one.
@Suite struct WindowsAreNamedByTheirLength {

    private func event(_ json: String) -> RateLimitsEvent? {
        RolloutParser.allEvents(inLines: ["""
        {"timestamp":"2026-08-27T10:00:00.000Z","type":"event_msg","payload":\
        {"type":"token_count","rate_limits":\(json)}}
        """]).first
    }

    @Test func aWeeklyWindowArrivingFirstIsStillWeekly() throws {
        let parsed = try #require(event("""
        {"limit_id":"codex","primary":{"used_percent":38.0,"window_minutes":10080,\
        "resets_at":1787457248},"secondary":null}
        """))
        #expect(parsed.windows.count == 1)
        #expect(parsed.windows.first?.id == "weekly")
        #expect(parsed.windows.first?.percent == 38.0)
    }

    @Test func theUsualPairIsStillReadTheUsualWay() throws {
        let parsed = try #require(event("""
        {"limit_id":"codex","primary":{"used_percent":5.0,"window_minutes":300,"resets_at":1},\
        "secondary":{"used_percent":23.0,"window_minutes":10080,"resets_at":2}}
        """))
        #expect(parsed.windows.map(\.id) == ["session", "weekly"])
        #expect(parsed.windows.map(\.percent) == [5.0, 23.0])
    }

    @Test func aShortWindowArrivingSecondIsStillTheShortOne() throws {
        let parsed = try #require(event("""
        {"limit_id":"codex","primary":{"used_percent":23.0,"window_minutes":10080,"resets_at":1},\
        "secondary":{"used_percent":5.0,"window_minutes":300,"resets_at":2}}
        """))
        #expect(parsed.windows.map(\.id) == ["weekly", "session"])
    }
}
