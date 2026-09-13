import Testing
import Foundation
import Preferences
import ClaudeProvider
@testable import StatusUI

/// The landing states numbers that come from constants in the code. Twice now a
/// change to a constant has left the page saying the old figure — correctly
/// spelled, confidently wrong, and noticed only by re-reading the page against
/// the source. The widget sizes were the first; "two HTTP requests per poll" was
/// the second, and it was true when written and false a few hours later.
///
/// Each check has two halves: the constant still holds the value the page
/// quotes, and the page still quotes it. Changing either one alone fails.
@Suite struct TheLandingQuotesTheCode {

    @Test func thePollIntervalsAreTheOnesThePageNames() throws {
        let page = try Self.page()
        #expect(Preferences.defaults.backgroundInterval == 300,
                "the landing says the background poll is five minutes apart")
        #expect(page.range(of: "five minutes apart", options: .caseInsensitive) != nil, "the landing no longer names the interval")

        #expect(Preferences.defaults.foregroundInterval == 60,
                "the landing says it polls once a minute while the window is open")
        #expect(page.range(of: "once a minute", options: .caseInsensitive) != nil, "the landing no longer names the interval")

        // Both are dials, and the page names them inside the section a reader
        // uses to weigh what this costs — the place where "you can ask less
        // often" is the answer somebody is looking for.
        let range = Preferences.intervalRange
        #expect(range == 30...3600, "the landing says thirty seconds to an hour")
        #expect(page.range(of: "thirty seconds and an hour", options: .caseInsensitive) != nil,
                "the landing states the poll intervals as though they were fixed")
    }

    @Test func theNameIsRememberedForAsLongAsThePageSays() throws {
        let page = try Self.page()
        #expect(ClaudeIdentityCache.lifetime == 6 * 60 * 60,
                "the landing says the name and plan are remembered for six hours")
        #expect(page.range(of: "six hours", options: .caseInsensitive) != nil, "the landing no longer names the lifetime")
    }

    @Test func theNotificationThresholdsAreTheOnesThePageNames() throws {
        let page = try Self.page()
        #expect(Set(Preferences.defaults.thresholds) == [80, 95],
                "the landing names 80% and 95% as what you get out of the box")
        #expect(page.range(of: "80% and 95%", options: .caseInsensitive) != nil, "the landing no longer names the thresholds")
        // The levels are the reader's: the Notifications pane adds and removes
        // them. The landing used to state the two defaults flatly, and this test
        // pinned it there — the same mistake as a test that demanded English
        // typography of all ten languages because the bug produced it.
        #expect(page.range(of: "out of the box", options: .caseInsensitive) != nil,
                "the landing states the defaults as though the levels were fixed")
    }

    /// "Ten languages" is on the page in words, so the count has to be read off
    /// the enum rather than matched as a digit.
    @Test func thereAreAsManyLanguagesAsThePageClaims() throws {
        let page = try Self.page()
        let translated = AppLanguage.allCases.filter { $0 != .system }
        #expect(translated.count == 10, "the landing says ten languages, found \(translated.count)")
        #expect(page.range(of: "Ten languages", options: .caseInsensitive) != nil, "the landing no longer names the count")
    }

    /// The page says no third-party code runs beside the reader's credentials.
    /// That is the kind of claim worth a check rather than a memory: one
    /// `.package(url:)` in either manifest makes it false, and adding one is a
    /// single convenient line.
    @Test func nothingThirdPartyIsPulledIn() throws {
        let root = Self.repositoryRoot

        let manifest = try String(contentsOf: root.appendingPathComponent("Packages/Core/Package.swift"),
                                  encoding: .utf8)
        #expect(!manifest.contains(".package("),
                "Package.swift declares an external package; the landing says there are none")

        // The Xcode project reaches packages by path or by URL. A path stays
        // inside this repository; a URL does not.
        let project = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        #expect(!project.contains("url:"),
                "project.yml pulls a package from a URL; the landing says there are none")

        let page = try Self.page()
        #expect(page.range(of: "Every import is either Apple", options: .caseInsensitive) != nil,
                "the landing no longer makes the claim this test is guarding")
    }

    /// The systems it needs were on the page only in the structured data: a
    /// search engine could read the requirement and a reader could not. Now the
    /// facts list carries it, and this holds the three copies together — the
    /// manifest the floor is actually set in, the sentence a person sees, and
    /// the `operatingSystem` a search result shows.
    ///
    /// The visible text is asked separately on purpose. Matching the whole file
    /// would find "macOS 14" in the JSON-LD and pass with the row deleted, which
    /// is the failure this test exists to catch.
    @Test func thePageNamesTheSystemsItNeeds() throws {
        let manifest = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent("Packages/Core/Package.swift"),
            encoding: .utf8)
        guard let mac = Self.firstGroup(#"\.macOS\(\.v(\d+)\)"#, in: manifest),
              let ios = Self.firstGroup(#"\.iOS\(\.v(\d+)\)"#, in: manifest) else {
            throw ScanIsLookingInTheWrongPlace(what: "platform floor", found: 0, least: 2)
        }

        let visibleNamesMac = try Self.visibleSays("macOS \(mac)")
        #expect(visibleNamesMac, "the landing does not tell a reader it needs macOS \(mac)")
        let visibleNamesIOS = try Self.visibleSays("iOS \(ios)")
        #expect(visibleNamesIOS, "the landing does not tell a reader the phone app needs iOS \(ios)")

        let markupAgrees = try Self.page()
            .contains("\"operatingSystem\":\"macOS \(mac), iOS \(ios)\"")
        #expect(markupAgrees, "the structured data names a different system than the manifest sets")

        // Two build systems describe the same floor, and only one of them is the
        // manifest above.
        let project = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent("project.yml"), encoding: .utf8)
        let projectAgreesOnMac = project.contains("macOS: \"\(mac).0\"")
        #expect(projectAgreesOnMac, "project.yml and Package.swift disagree about the macOS floor")
        let projectAgreesOnIOS = project.contains("deploymentTarget: \"\(ios).0\"")
        #expect(projectAgreesOnIOS, "project.yml and Package.swift disagree about the iOS floor")
    }

    /// The page names techniques by name, in the section addressed to people who
    /// read that part — the ones a developer checks first and would notice being
    /// wrong. Each is true today, and nothing joined the sentence to the code:
    /// swapping PKCE for a plain redirect leaves the page saying the old thing
    /// in confident English.
    @Test func theTechniquesThePageNamesAreTheOnesInUse() throws {
        let root = Self.repositoryRoot

        let login = try String(
            contentsOf: root.appendingPathComponent(
                "Packages/Core/Sources/ClaudeProvider/OAuthLogin.swift"),
            encoding: .utf8)
        #expect(login.contains("code_challenge_method"),
                "the sign-in no longer sends a PKCE challenge, which the landing names")
        #expect(try Self.visibleSays("PKCE"),
                "the landing no longer names how an account is added")

        // The page's claim; `CoreStaysPortable` holds the code to it. This is the
        // other half — that the page still makes the claim being held.
        #expect(try Self.visibleSays("no AppKit"),
                "the landing no longer says the core is free of AppKit")
    }

    /// Quiet hours are the one promise on the page about something *not*
    /// happening twice over: nothing arrives during them, and nothing arrives
    /// afterwards to make up for it. The behaviour is held by
    /// `theNightsCrossingIsNotDeliveredInTheMorning` in the Monitoring tests;
    /// this is the other half, that the page still promises what that holds.
    @Test func thePageStillPromisesTheQuietHoursStayQuiet() throws {
        #expect(try Self.visibleSays("nothing is delivered late"),
                "the landing no longer promises the night's events are dropped rather than queued")
    }

    private static func firstGroup(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    /// The page with `<style>` and `<script>` removed — what a person actually
    /// reads. Takes the phrase, not the document: see `HowToAskADocument`.
    ///
    /// `.dotMatchesLineSeparators` is the whole point. Written without it the
    /// strip silently removed nothing, because both blocks span lines and `.`
    /// stops at a newline by default — so the check found "macOS 14" in the
    /// JSON-LD and passed with the visible row deleted. That is precisely the
    /// case it was written to catch, and it took deleting the row to find out.
    private static func visibleSays(_ phrase: String) throws -> Bool {
        var text = try String(
            contentsOf: repositoryRoot.appendingPathComponent("site/index.html"), encoding: .utf8)
        for tag in ["style", "script"] {
            guard let regex = try? NSRegularExpression(
                pattern: "<\(tag)[^>]*>.*?</\(tag)>",
                options: [.dotMatchesLineSeparators, .caseInsensitive]) else { continue }
            text = regex.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }
        // Both blocks are there to be removed; removing neither is the bug above.
        guard !text.contains("<style"), !text.contains("<script") else {
            throw ScanIsLookingInTheWrongPlace(what: "stripped block", found: 0, least: 2)
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ").says(phrase)
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// The page wrapped at 110 columns, so a phrase worth checking straddles a
    /// line break sooner or later — "once a minute" did, the first time the copy
    /// was shortened. Whitespace is collapsed before matching: the file being
    /// wrapped is not the sentence being absent. The README and the preview
    /// guards each had to learn this separately.
    // Matched without regard to case. The rule is that the page names the
    // figure, not that the phrase sits mid-sentence: "five minutes apart" moved
    // to the start of one when that fact was split in two, and the guard refused
    // it. Third time this family of checks has been written against the shape of
    // the text rather than the thing it means — the README's "all four sizes"
    // and the plans' note were the other two.
    private static func page() throws -> String {
        let text = try String(
            contentsOf: repositoryRoot.appendingPathComponent("site/index.html"),
            encoding: .utf8
        )
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
