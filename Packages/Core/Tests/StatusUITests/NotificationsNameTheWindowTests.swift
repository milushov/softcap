import Testing
import Foundation
@testable import Monitoring
@testable import StatusUI

/// Every account lives under two limits at once — the five-hour session and
/// the week — and both can cross the same threshold on the same evening. That
/// happened: the weekly limit reached 80%, and the session limit reached its
/// own 80% under an hour later. Both notifications read "account: 80% of
/// limit. About 20% left." — the same words for two different facts. A reader
/// cannot tell the second fact from the app repeating the first, and reported
/// it as a duplicate.
///
/// So a notification names the window it is about, in every language, and the
/// same rule holds for the recovery message — "the limit reset" is only
/// useful if it says which one.
@MainActor @Suite struct NotificationsNameTheWindow {

    private static func crossed(_ windowID: String, level: Int = 80) -> ThresholdEvent {
        ThresholdEvent(accountID: "claude/a", windowID: windowID,
                       accountName: "a@example.com", kind: .crossed(level))
    }

    private static func recovered(_ windowID: String) -> ThresholdEvent {
        ThresholdEvent(accountID: "claude/a", windowID: windowID,
                       accountName: "a@example.com", kind: .recovered)
    }

    /// The incident, replayed: one account, one threshold, two windows.
    /// The titles must differ — in every language, or a translation could
    /// quietly collapse the two facts back into one.
    @Test func theTwoWindowsNeverReadTheSame() {
        let loc = Localization()
        for language in AppLanguage.allCases where language != .system {
            loc.use(language)
            let session = loc.notificationTitle(for: Self.crossed("session"))
            let weekly = loc.notificationTitle(for: Self.crossed("weekly"))
            #expect(session != weekly,
                    "\(language.rawValue): both windows produce “\(session)”")
        }
    }

    @Test func theTitleSaysWhichLimitWasCrossed() {
        let loc = Localization()
        loc.use(.english)
        #expect(loc.notificationTitle(for: Self.crossed("session"))
                == "a@example.com: 80% of the 5-hour limit")
        #expect(loc.notificationTitle(for: Self.crossed("weekly"))
                == "a@example.com: 80% of the weekly limit")
    }

    /// Recovery has the same two-window shape: the five-hour limit resets
    /// several times a day, and hearing "the limit reset" while the weekly one
    /// sits at 88% would be a false all-clear.
    @Test func recoverySaysWhichLimitReset() {
        let loc = Localization()
        loc.use(.english)
        #expect(loc.notificationBody(for: Self.recovered("session"))
                == "The 5-hour limit reset, you can come back.")
        #expect(loc.notificationBody(for: Self.recovered("weekly"))
                == "The weekly limit reset, you can come back.")

        for language in AppLanguage.allCases where language != .system {
            loc.use(language)
            let session = loc.notificationBody(for: Self.recovered("session"))
            let weekly = loc.notificationBody(for: Self.recovered("weekly"))
            #expect(session != weekly,
                    "\(language.rawValue): both recoveries produce “\(session)”")
        }
    }

    /// A window kind this build has never heard of still gets the old,
    /// unnamed wording rather than nothing — the same stance the providers
    /// take on unfamiliar window kinds in a response.
    @Test func anUnfamiliarWindowKeepsTheOldWords() {
        let loc = Localization()
        loc.use(.english)
        #expect(loc.notificationTitle(for: Self.crossed("monthly"))
                == "a@example.com: 80% of limit")
        #expect(loc.notificationBody(for: Self.recovered("monthly"))
                == "The limit reset, you can come back.")
    }

    /// The body carries the remainder, and the last step keeps its warning.
    @Test func theBodyStillCountsWhatIsLeft() {
        let loc = Localization()
        loc.use(.english)
        #expect(loc.notificationBody(for: Self.crossed("weekly", level: 80))
                == "About 20% left.")
        #expect(loc.notificationBody(for: Self.crossed("session", level: 95))
                == "Almost exhausted — time to switch.")
    }
}
