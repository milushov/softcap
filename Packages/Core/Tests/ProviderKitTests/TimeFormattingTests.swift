import Testing
import Foundation
@testable import ProviderKit

// The arithmetic is kept in constants: inside the `#require` macro the
// compiler cannot infer types for compound expressions.
private let minutes47: TimeInterval = 2_820
private let hours3min39: TimeInterval = 13_140
private let days5: TimeInterval = 517_140
private let seconds59: TimeInterval = 59

@Test func splitsMinutesOnlyUnderAnHour() throws {
    let r = try #require(RemainingTime(minutes47))
    #expect(r.days == 0)
    #expect(r.hours == 0)
    #expect(r.minutes == 47)
}

@Test func splitsHoursAndMinutes() throws {
    let r = try #require(RemainingTime(hours3min39))
    #expect(r.hours == 3)
    #expect(r.minutes == 39)
}

@Test func splitsDaysAndHours() throws {
    let r = try #require(RemainingTime(days5))
    #expect(r.days == 5)
    #expect(r.hours == 23)
    #expect(r.minutes == 39)
}

@Test func elapsedIntervalHasNoRemainder() {
    // Showing "minus three minutes" is meaningless.
    #expect(RemainingTime(-120) == nil)
}

@Test func roundsDownRatherThanUp() throws {
    // 59 seconds is still zero minutes, not one.
    let r = try #require(RemainingTime(seconds59))
    #expect(r.minutes == 0)
}

@Test func daysHideMinutesAsInsignificant() throws {
    let r = try #require(RemainingTime(days5))
    let units = r.significantUnits
    #expect(units.major == .days(5))
    #expect(units.minor == .hours(23))
}

@Test func hoursKeepMinutes() throws {
    let units = try #require(RemainingTime(hours3min39)).significantUnits
    #expect(units.major == .hours(3))
    #expect(units.minor == .minutes(39))
}

@Test func minutesStandAlone() throws {
    let units = try #require(RemainingTime(minutes47)).significantUnits
    #expect(units.major == .minutes(47))
    #expect(units.minor == nil)
}
