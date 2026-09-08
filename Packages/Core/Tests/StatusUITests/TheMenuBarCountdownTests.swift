import Testing
import Foundation
@testable import StatusUI

/// The countdown in the menu bar, which is looked at more than anything else the
/// app draws and was tested by nothing.
///
/// The plan for the first prototype specified two cases for it — a clock under a
/// day, days collapsed above one — and neither was written. The function survived
/// the localisation rewrite that replaced `formatRemaining` with `RemainingTime`,
/// and the tests that were meant to cover it did not.
@MainActor
@Suite struct TheMenuBarCountdown {

    private func english() -> Localization {
        let loc = Localization()
        loc.use(.english)
        return loc
    }

    @Test func underAnHourItIsStillAClock() {
        #expect(english().remainingCompact(47 * 60) == "0:47")
    }

    @Test func hoursAndMinutesReadAsATime() {
        #expect(english().remainingCompact(3 * 3600 + 39 * 60) == "3:39")
    }

    /// Two digits after the colon, always. "2:4" is not a time.
    @Test func minutesArePadded() {
        #expect(english().remainingCompact(2 * 3600 + 4 * 60) == "2:04")
    }

    /// Above a day the clock would be misleading — "23:00" reads as tonight, not
    /// as tomorrow — so it collapses to whole days.
    @Test func pastADayItCollapses() {
        let text = english().remainingCompact(5 * 86400 + 23 * 3600)
        #expect(text.contains("5"))
        #expect(!text.contains(":"), "a countdown of days should not look like a clock")
    }

    @Test func nothingLeftIsADash() {
        #expect(english().remainingCompact(nil) == "—")
        #expect(english().remainingCompact(-120) == "—")
    }

    /// The days part comes from the catalogue and is not the same word twice.
    @Test func theDayUnitIsTranslated() {
        var seen: Set<String> = []
        for language in AppLanguage.allCases where language != .system {
            let loc = Localization()
            loc.use(language)
            let text = loc.remainingCompact(3 * 86400)
            #expect(!text.isEmpty, "\(language.rawValue) has no compact form")
            #expect(text.contains("3") || text.rangeOfCharacter(from: .decimalDigits) != nil,
                    "\(language.rawValue): \(text) names no number")
            seen.insert(text)
        }
        #expect(seen.count > 1, "every language produced the same string")
    }
}
