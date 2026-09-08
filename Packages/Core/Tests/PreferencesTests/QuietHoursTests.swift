import Testing
import Foundation
@testable import Preferences

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func at(_ hour: Int, _ minute: Int) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 8, day: 30, hour: hour, minute: minute))!
}

@Test func daytimeWindowContainsOnlyItsHours() {
    let hours = QuietHours(startMinute: 13 * 60, endMinute: 14 * 60)   // 13:00–14:00
    #expect(hours.contains(at(13, 30), calendar: utc))
    #expect(hours.contains(at(12, 59), calendar: utc) == false)
    #expect(hours.contains(at(14, 0), calendar: utc) == false)   // the end is excluded
}

@Test func windowAcrossMidnightWorksOnBothSides() {
    let hours = QuietHours(startMinute: 23 * 60, endMinute: 9 * 60)    // 23:00–09:00
    #expect(hours.contains(at(23, 30), calendar: utc))   // evening
    #expect(hours.contains(at(2, 0), calendar: utc))     // night
    #expect(hours.contains(at(8, 59), calendar: utc))    // morning
    #expect(hours.contains(at(9, 0), calendar: utc) == false)
    #expect(hours.contains(at(15, 0), calendar: utc) == false)
}

@Test func startEqualToEndMeansAlwaysQuiet() {
    // The degenerate case: the user set both ends to the same time.
    // Read as "quiet around the clock" rather than "never".
    let hours = QuietHours(startMinute: 60, endMinute: 60)
    #expect(hours.contains(at(0, 30), calendar: utc))
    #expect(hours.contains(at(12, 0), calendar: utc))
}
