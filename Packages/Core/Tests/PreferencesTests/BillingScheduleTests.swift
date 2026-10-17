import Testing
import Foundation
@testable import Preferences

@Suite struct PaymentDays {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func days(_ dates: [Date]) -> [String] {
        dates.map {
            let c = calendar.dateComponents([.year, .month, .day], from: $0)
            return "\(c.year!)-\(c.month!)-\(c.day!)"
        }
    }

    @Test func monthlyFallsOnceInEachMonthOfTheRange() {
        let schedule = BillingSchedule(dayOfMonth: 15)
        let found = schedule.payments(
            from: date(2026, 8, 20), to: date(2026, 11, 20), calendar: calendar)
        #expect(days(found) == ["2026-9-15", "2026-10-15", "2026-11-15"])
    }

    @Test func aDayPastTheMonthsEndClampsToItsLastDay() {
        let schedule = BillingSchedule(dayOfMonth: 31)
        let found = schedule.payments(
            from: date(2027, 1, 1), to: date(2027, 4, 30), calendar: calendar)
        #expect(days(found) == ["2027-1-31", "2027-2-28", "2027-3-31", "2027-4-30"])
    }

    @Test func aLeapFebruaryClampsToTheTwentyNinth() {
        let schedule = BillingSchedule(dayOfMonth: 30)
        let found = schedule.payments(
            from: date(2028, 2, 1), to: date(2028, 2, 29), calendar: calendar)
        #expect(days(found) == ["2028-2-29"])
    }

    @Test func yearlyFallsOnlyInItsMonth() {
        let schedule = BillingSchedule(dayOfMonth: 5, period: .yearly(month: 3))
        let found = schedule.payments(
            from: date(2026, 1, 1), to: date(2027, 12, 31), calendar: calendar)
        #expect(days(found) == ["2026-3-5", "2027-3-5"])
    }

    @Test func yearlyOnThe31stClampsInAShortMonth() {
        let schedule = BillingSchedule(dayOfMonth: 31, period: .yearly(month: 2))
        let found = schedule.payments(
            from: date(2027, 1, 1), to: date(2027, 12, 31), calendar: calendar)
        #expect(days(found) == ["2027-2-28"])
    }

    @Test func aDayOutsideTheRangeIsLeftOutEvenInsideItsMonth() {
        let schedule = BillingSchedule(dayOfMonth: 10)
        let found = schedule.payments(
            from: date(2026, 10, 11), to: date(2026, 10, 30), calendar: calendar)
        #expect(found.isEmpty)
    }

    @Test func aBackwardsRangeIsEmpty() {
        let schedule = BillingSchedule(dayOfMonth: 10)
        #expect(schedule.payments(
            from: date(2026, 10, 30), to: date(2026, 10, 1), calendar: calendar).isEmpty)
    }

    @Test func outOfRangeInputIsClamped() {
        #expect(BillingSchedule(dayOfMonth: 0).dayOfMonth == 1)
        #expect(BillingSchedule(dayOfMonth: 99).dayOfMonth == 31)
        #expect(BillingSchedule(dayOfMonth: 1, period: .yearly(month: 13)).period
                == .yearly(month: 12))
    }

    @Test func aSettingsFileWithoutBillingStillDecodes() throws {
        // Written by a build that had never heard of billing days.
        let json = #"{"appearance":"dark","hiddenAccounts":["claude/a"]}"#
        let decoded = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        #expect(decoded.billing.isEmpty)
        #expect(decoded.appearance == .dark)
        #expect(decoded.hiddenAccounts == ["claude/a"])
    }

    @Test func aScheduleSurvivesARoundTrip() throws {
        var p = Preferences.defaults
        p.billing["claude/a"] = BillingSchedule(dayOfMonth: 12)
        p.billing["codex/b"] = BillingSchedule(dayOfMonth: 3, period: .yearly(month: 7))
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(Preferences.self, from: data)
        #expect(back.billing == p.billing)
    }
}
