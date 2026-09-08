import Testing
import Foundation
import ProviderKit
import Preferences
@testable import Monitoring

private func snap(_ percent: Double) -> [AccountSnapshot] {
    [AccountSnapshot(
        id: "claude/u", provider: .claude, displayName: "a@b.c", planLabel: "Max",
        windows: [LimitWindow(id: "weekly", percent: percent, resetsAt: nil)],
        freshness: .live(Date(timeIntervalSince1970: 0)), failure: nil
    )]
}

@Test func firstReadingIsSilent() {
    var tracker = ThresholdTracker()
    #expect(tracker.events(for: snap(97), now: moment(12)).isEmpty)
}

@Test func firesOnceWhenCrossingEighty() {
    var tracker = ThresholdTracker()
    _ = tracker.events(for: snap(70), now: moment(12))

    let events = tracker.events(for: snap(81), now: moment(12))
    #expect(events.count == 1)
    #expect(events[0].kind == .crossed(80))
    #expect(events[0].accountName == "a@b.c")
}

@Test func staysSilentWhileAboveThreshold() {
    var tracker = ThresholdTracker()
    _ = tracker.events(for: snap(70), now: moment(12))
    _ = tracker.events(for: snap(81), now: moment(12))

    #expect(tracker.events(for: snap(85), now: moment(12)).isEmpty)
    #expect(tracker.events(for: snap(89), now: moment(12)).isEmpty)
}

@Test func firesAgainForTheHigherThreshold() {
    var tracker = ThresholdTracker()
    _ = tracker.events(for: snap(70), now: moment(12))
    _ = tracker.events(for: snap(81), now: moment(12))

    let events = tracker.events(for: snap(96), now: moment(12))
    #expect(events.map(\.kind) == [.crossed(95)])
}

@Test func jumpingPastBothReportsOnlyTheHigher() {
    var tracker = ThresholdTracker()
    _ = tracker.events(for: snap(10), now: moment(12))

    let events = tracker.events(for: snap(99), now: moment(12))
    #expect(events.map(\.kind) == [.crossed(95)])
}

@Test func reportsRecoveryAfterReset() {
    var tracker = ThresholdTracker()
    _ = tracker.events(for: snap(10), now: moment(12))
    _ = tracker.events(for: snap(96), now: moment(12))

    let events = tracker.events(for: snap(3), now: moment(12))
    #expect(events.map(\.kind) == [.recovered])
}

@Test func canFireAgainAfterRecovery() {
    var tracker = ThresholdTracker()
    _ = tracker.events(for: snap(10), now: moment(12))
    _ = tracker.events(for: snap(96), now: moment(12))
    _ = tracker.events(for: snap(3), now: moment(12))

    #expect(tracker.events(for: snap(82), now: moment(12)).map(\.kind) == [.crossed(80)])
}

@Test func failedAccountProducesNoEvents() {
    var tracker = ThresholdTracker()
    _ = tracker.events(for: snap(10), now: moment(12))

    let broken = [AccountSnapshot(
        id: "claude/u", provider: .claude, displayName: "a@b.c", planLabel: "Max",
        windows: [], freshness: .live(Date(timeIntervalSince1970: 0)),
        failure: ProviderFailure(kind: .network, diagnostic: "no network")
    )]
    #expect(tracker.events(for: broken, now: moment(12)).isEmpty)
}

// ===== configurable thresholds, scope and quiet hours =====

private var utcCalendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func moment(_ hour: Int) -> Date {
    utcCalendar.date(from: DateComponents(year: 2026, month: 8, day: 30, hour: hour))!
}

@Test func customThresholdFiresAtItsOwnLevel() {
    var tracker = ThresholdTracker(
        thresholds: [50], notifyOnRecovery: true, scope: .both,
        quietHours: nil, calendar: utcCalendar
    )
    _ = tracker.events(for: snap(10), now: moment(12))
    #expect(tracker.events(for: snap(51), now: moment(12)).map(\.kind) == [.crossed(50)])
}

@Test func emptyThresholdsSilenceLoadEventsButKeepRecovery() {
    var tracker = ThresholdTracker(
        thresholds: [], notifyOnRecovery: true, scope: .both,
        quietHours: nil, calendar: utcCalendar
    )
    _ = tracker.events(for: snap(10), now: moment(12))
    #expect(tracker.events(for: snap(99), now: moment(12)).isEmpty)
    #expect(tracker.events(for: snap(5), now: moment(12)).map(\.kind) == [.recovered])
}

@Test func recoveryCanBeTurnedOff() {
    var tracker = ThresholdTracker(
        thresholds: [80], notifyOnRecovery: false, scope: .both,
        quietHours: nil, calendar: utcCalendar
    )
    _ = tracker.events(for: snap(10), now: moment(12))
    _ = tracker.events(for: snap(90), now: moment(12))
    #expect(tracker.events(for: snap(5), now: moment(12)).isEmpty)
}

@Test func scopeLimitsWhichWindowsReport() {
    var tracker = ThresholdTracker(
        thresholds: [80], notifyOnRecovery: true, scope: .session,
        quietHours: nil, calendar: utcCalendar
    )
    // snap(...) yields a single window with id "weekly" — outside this scope
    _ = tracker.events(for: snap(10), now: moment(12))
    #expect(tracker.events(for: snap(90), now: moment(12)).isEmpty)
}

@Test func quietHoursSuppressEventsInsideTheWindow() {
    var tracker = ThresholdTracker(
        thresholds: [80], notifyOnRecovery: true, scope: .both,
        quietHours: QuietHours(startMinute: 23 * 60, endMinute: 9 * 60),
        calendar: utcCalendar
    )
    _ = tracker.events(for: snap(10), now: moment(12))
    #expect(tracker.events(for: snap(90), now: moment(2)).isEmpty)
}

/// The name said the opposite of the assertion for a week: "do not lose the
/// crossing afterwards" reads as "it arrives later", and the test asserts that
/// nothing arrives at all. The landing puts it plainly — "nothing is delivered
/// late to make up for it" — and that is what this holds.
@Test func theNightsCrossingIsNotDeliveredInTheMorning() {
    var tracker = ThresholdTracker(
        thresholds: [80], notifyOnRecovery: true, scope: .both,
        quietHours: QuietHours(startMinute: 23 * 60, endMinute: 9 * 60),
        calendar: utcCalendar
    )
    _ = tracker.events(for: snap(10), now: moment(12))
    _ = tracker.events(for: snap(90), now: moment(2))
    // The reading is already recorded, so there is no second crossing — which
    // is right: delivering the night's notifications in the morning wakes
    // somebody with news that has gone stale.
    #expect(tracker.events(for: snap(92), now: moment(12)).isEmpty)
}

// MARK: - What it remembers has to outlive the process

/// The whole point of the seed. A relaunch used to be indistinguishable from a
/// first run: nothing below the threshold to have crossed from, so an account
/// already past one never produced a crossing at all — not late, never, until
/// the limit reset and climbed again. Somebody watched a weekly window sit at
/// 91% having been told nothing.
@Test func aSeededTrackerSeesTheCrossingAFreshOneCannot() {
    var fresh = ThresholdTracker()
    #expect(fresh.events(for: snap(91), now: moment(12)).isEmpty,
            "a first reading is silent, which is what makes the seed necessary")

    var seeded = ThresholdTracker()
    seeded.seed(from: snap(70))
    let events = seeded.events(for: snap(91), now: moment(12))
    #expect(events.count == 1)
    #expect(events[0].kind == .crossed(80))
}

/// Seeding records where things stood; it does not announce it. Whatever
/// happened before the app started is not news it can honestly deliver.
@Test func seedingByItselfSaysNothing() {
    var tracker = ThresholdTracker()
    tracker.seed(from: snap(97))
    #expect(tracker.events(for: snap(97), now: moment(12)).isEmpty)
    #expect(tracker.events(for: snap(98), now: moment(12)).isEmpty,
            "already past both thresholds when it started, so there is no crossing")
}

/// A reading that was already over stays over: the seed must not turn the first
/// live reading into a crossing that never happened.
@Test func seedingAboveAThresholdDoesNotInventACrossing() {
    var tracker = ThresholdTracker()
    tracker.seed(from: snap(85))
    #expect(tracker.events(for: snap(88), now: moment(12)).isEmpty)
    // But the one it has not passed yet still fires.
    #expect(tracker.events(for: snap(96), now: moment(12)).map(\.kind) == [.crossed(95)])
}

/// Changing the quiet hours is not a reason to forget where every account stood.
///
/// Both readings are given a moment. Written without one, `events(for:)` defaults
/// to the actual clock, and the quiet hours this passes — one o'clock to two —
/// made the test pass all evening and fail at 01:00, which is worse than not
/// having it. The calendar is UTC and the hours are the day's, so the answer
/// cannot depend on when it is run or where.
@Test func theBaselineSurvivesARebuild() {
    var before = ThresholdTracker(calendar: utcCalendar)
    _ = before.events(for: snap(70), now: moment(12))

    var after = ThresholdTracker(quietHours: QuietHours(startMinute: 60, endMinute: 120),
                                 calendar: utcCalendar)
    after.restore(before.baseline)
    #expect(after.events(for: snap(81), now: moment(12)).map(\.kind) == [.crossed(80)])
}

@Test func anEmptyBaselineLeavesTheTrackerFresh() {
    let untouched = ThresholdTracker()
    #expect(untouched.baseline.isEmpty)

    var adopted = ThresholdTracker()
    adopted.restore(untouched.baseline)
    #expect(adopted.events(for: snap(91), now: moment(12)).isEmpty,
            "nothing was carried, so the first reading is still a first reading")
}

/// A failed account has no percentage worth remembering, and seeding from one
/// would put a stale figure under the next live reading.
@Test func seedingSkipsAFailedAccount() {
    let broken = [AccountSnapshot(
        id: "claude/u", provider: .claude, displayName: "a@b.c", planLabel: "Max",
        windows: [LimitWindow(id: "weekly", percent: 70, resetsAt: nil)],
        freshness: .live(Date(timeIntervalSince1970: 0)),
        failure: ProviderFailure(kind: .needsLogin, diagnostic: "x")
    )]
    var tracker = ThresholdTracker()
    tracker.seed(from: broken)
    #expect(tracker.baseline.isEmpty)
}

/// The moment stays required.
///
/// A test set quiet hours of one to two and left `now` to the clock: it passed
/// all evening, was committed green, and failed at 01:00 with nothing changed.
/// Removing the default made that unwritable. Putting it back compiles and breaks
/// nothing, which is exactly why it needs saying out loud rather than leaving to
/// the compiler.
@Test func decidingByTheClockRequiresSayingWhichMoment() throws {
    let source = try String(
        contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // MonitoringTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // Core
            .appendingPathComponent("Sources/Monitoring/ThresholdTracker.swift"),
        encoding: .utf8)
    #expect(source.contains("now: Date\n") || source.contains("now: Date)"),
            "ThresholdTracker no longer takes a moment at all")
    #expect(!source.contains("now: Date = "), """
        events(for:now:) defaults its moment again, so a check that turns on the \
        quiet hours can be written without one and will pass until the hour comes
        """)
}
