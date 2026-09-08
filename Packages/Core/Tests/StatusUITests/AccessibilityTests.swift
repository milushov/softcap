import Testing
import Foundation
import ProviderKit
@testable import StatusUI

/// The spoken summary is the only description a screen reader gets: the row
/// itself is collapsed into one element, so anything missing from the sentence
/// is missing from the app entirely.
@MainActor
@Suite struct SpokenSummary {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(
        windows: [LimitWindow],
        failure: ProviderFailure? = nil,
        freshness: Freshness? = nil,
        plan: String = "Max 20x"
    ) -> AccountSnapshot {
        AccountSnapshot(
            id: "claude/abc",
            provider: .claude,
            displayName: "name@example.com",
            planLabel: plan,
            windows: windows,
            freshness: freshness ?? .live(now),
            failure: failure
        )
    }

    private func english() -> Localization {
        let loc = Localization()
        loc.use(.english)
        return loc
    }

    @Test func namesTheServiceAccountAndPlan() {
        let loc = english()
        let text = loc.spokenSummary(for: snapshot(windows: []), now: now)
        #expect(text.contains("Claude"))
        #expect(text.contains("name@example.com"))
        #expect(text.contains("Max 20x"))
    }

    @Test func skipsAnEmptyPlanRatherThanLeavingADanglingComma() {
        let loc = english()
        let text = loc.spokenSummary(for: snapshot(windows: [], plan: ""), now: now)
        #expect(!text.contains(", ."))
        #expect(!text.hasSuffix(", "))
    }

    /// The screen says "5h" and "23%"; spelled out, "5h" is read as letters.
    @Test func spellsWindowNamesAndTimeInWords() {
        let loc = english()
        let window = LimitWindow(id: "session", percent: 23,
                                 resetsAt: now.addingTimeInterval(3600 * 3 + 60 * 39))
        let text = loc.spokenSummary(for: snapshot(windows: [window]), now: now)
        #expect(text.contains("Five-hour"))
        #expect(text.contains("23%"))
        #expect(text.contains("hours"))
        #expect(text.contains("minutes"))
        #expect(!text.contains("3h 39m"))
    }

    @Test func describesEveryWindowNotJustTheWorst() {
        let loc = english()
        let text = loc.spokenSummary(for: snapshot(windows: [
            LimitWindow(id: "session", percent: 23, resetsAt: now.addingTimeInterval(3600)),
            LimitWindow(id: "weekly", percent: 45, resetsAt: now.addingTimeInterval(86400 * 5)),
        ]), now: now)
        #expect(text.contains("Five-hour"))
        #expect(text.contains("Weekly"))
        #expect(text.contains("23%"))
        #expect(text.contains("45%"))
    }

    /// A window with no reset time must still be spoken — dropping the sentence
    /// would silently hide the percentage.
    @Test func speaksAWindowWithNoResetTime() {
        let loc = english()
        let window = LimitWindow(id: "weekly", percent: 60, resetsAt: nil)
        let text = loc.spokenSummary(for: snapshot(windows: [window]), now: now)
        #expect(text.contains("60%"))
        #expect(!text.contains("left"))
    }

    /// A reset already in the past would otherwise be spoken as a negative
    /// interval, or as an empty phrase with a dangling "left".
    @Test func omitsRemainingTimeWhenTheResetHasPassed() {
        let loc = english()
        let window = LimitWindow(id: "weekly", percent: 60,
                                 resetsAt: now.addingTimeInterval(-3600))
        let text = loc.spokenSummary(for: snapshot(windows: [window]), now: now)
        #expect(text.contains("60%"))
        #expect(!text.contains("left"))
    }

    @Test func speaksTheFailureInsteadOfTheNumbers() {
        let loc = english()
        let text = loc.spokenSummary(
            for: snapshot(windows: [LimitWindow(id: "weekly", percent: 60, resetsAt: nil)],
                          failure: ProviderFailure(kind: .needsLogin, diagnostic: "401")),
            now: now)
        #expect(text.contains(loc.failureText(.needsLogin)))
        #expect(!text.contains("60%"))
        #expect(!text.contains("401"), "the diagnostic is written for the log, not for a person")
    }

    /// The badge that says the reading is old is a colour and a small label;
    /// neither survives into speech unless it is in the sentence.
    @Test func mentionsThatTheReadingIsASnapshot() {
        let loc = english()
        let old = now.addingTimeInterval(-86400 * 2)
        let text = loc.spokenSummary(
            for: snapshot(windows: [], freshness: .snapshot(old)), now: now)
        #expect(text.contains("Data from"))
    }

    @Test func doesNotMentionAgeForALiveReading() {
        let loc = english()
        let text = loc.spokenSummary(
            for: snapshot(windows: [], freshness: .live(now)), now: now)
        #expect(!text.contains("Data from"))
    }

    /// The point of `activeLocale`: a formatter left on the system locale would
    /// speak English units inside an otherwise Russian sentence.
    @Test func speaksTimeInTheChosenLanguageNotTheSystemOne() {
        let loc = Localization()
        loc.use(.russian)
        let window = LimitWindow(id: "session", percent: 23,
                                 resetsAt: now.addingTimeInterval(3600 * 3))
        let text = loc.spokenSummary(for: snapshot(windows: [window]), now: now)
        #expect(!text.contains("hours"), "the duration stayed English: \(text)")
        #expect(text.range(of: "[А-Яа-я]", options: .regularExpression) != nil)
    }

    @Test func everyLanguageProducesANonEmptySentence() {
        let window = LimitWindow(id: "weekly", percent: 45,
                                 resetsAt: now.addingTimeInterval(86400 * 5))
        for language in AppLanguage.allCases {
            let loc = Localization()
            loc.use(language)
            let text = loc.spokenSummary(for: snapshot(windows: [window]), now: now)
            // The share as *this* language writes it. Asserting the literal
            // "45%" was asserting English typography for all ten, and it passed
            // only because the sentence was assembling the sign by hand — which
            // three catalogues did in the wrong place.
            #expect(text.contains(loc.percent(45)), "\(language.rawValue): \(text)")
            #expect(!text.contains("%1$@"), "\(language.rawValue): placeholder left unfilled")
            #expect(!text.contains("%2$@"), "\(language.rawValue): placeholder left unfilled")
            #expect(!text.contains("%3$@"), "\(language.rawValue): placeholder left unfilled")
        }
    }
}

/// Percentages are typography, not arithmetic: the spacing and the sign's side
/// belong to the language.
@MainActor
@Suite struct PercentSpelling {

    private func loc(_ language: AppLanguage) -> Localization {
        let l = Localization()
        l.use(language)
        return l
    }

    @Test func englishHasNoSpaceBeforeTheSign() {
        #expect(loc(.english).percent(23) == "23%")
    }

    /// Russian, French and Spanish typography puts a non-breaking space there.
    /// Writing "\(n)%" by hand got this wrong in all three.
    @Test func russianFrenchAndSpanishSeparateTheSign() {
        for language in [AppLanguage.russian, .french, .spanish] {
            let text = loc(language).percent(23)
            #expect(text.contains("\u{00A0}") || text.contains("\u{202F}"),
                    "\(language.rawValue): no separator in \(text.debugDescription)")
        }
    }

    @Test func roundsRatherThanTruncates() {
        #expect(loc(.english).percent(22.6) == "23%")
        #expect(loc(.english).percent(0.4) == "0%")
    }

    @Test func everyLanguageSpellsTheEndsOfTheRange() {
        for language in AppLanguage.allCases {
            for value in [0.0, 5.0, 100.0] {
                let text = loc(language).percent(value)
                #expect(!text.isEmpty, "\(language.rawValue) produced nothing for \(value)")
                #expect(text.rangeOfCharacter(from: .decimalDigits) != nil, "\(language.rawValue): \(text)")
            }
        }
    }
}
