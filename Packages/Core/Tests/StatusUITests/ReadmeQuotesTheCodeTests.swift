import Testing
import Foundation
@testable import Monitoring
@testable import StatusUI

/// The README states figures, and figures drift.
///
/// The landing has been guarded this way since it was written, because a page
/// that quotes the code is worth nothing once the code moves. The README makes
/// the same kind of claim — how often a reading is kept, how long history lives,
/// how many settings sections there are — and nothing was watching it. It is the
/// first thing anybody reads about this project.
///
/// Each check names the constant, so changing the constant fails here until the
/// sentence is changed too.
@Suite struct TheReadmeQuotesTheCode {

    @Test func theHistoryFiguresAreTheOnesTheCodeUses() throws {
        let readme = try Self.readme()

        #expect(UsageHistory.significantChange == 1.0,
                "the README says a reading is kept when the figure moves by a point")
        #expect(try Self.readmeSays("moves by a point"), "the README no longer says it")

        #expect(UsageHistory.minimumSpacing == 5 * 60,
                "the README says at most every five minutes")
        #expect(try Self.readmeSays("at most every five minutes"), "the README no longer says it")

        #expect(UsageHistory.heartbeat == 30 * 60,
                "the README says one every half hour regardless")
        #expect(try Self.readmeSays("every half hour regardless"), "the README no longer says it")

        let days = Int(UsageHistory.retention / 86_400)
        #expect(days == 35, "the README says pruned after 35 days")
        #expect(try Self.readmeSays("pruned after \(days) days"),
                "the README names a retention the code does not use")
    }

    /// One pane file per section, plus About. "Seven" is a number somebody will
    /// add an eighth to — and somebody did, when app updates needed a screen of
    /// their own and the one called Updates turned out to be about polling.
    @Test func theSettingsSectionsAreCounted() throws {
        let panes = try FileManager.default
            .contentsOfDirectory(at: Self.root.appendingPathComponent("App/Settings"),
                                 includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix("Pane.swift") }
        #expect(panes.count == 8, "there are \(panes.count) panes, not eight")
        #expect(try Self.readmeSays("Eight sections"),
                "the README no longer counts the settings sections")
    }

    @Test func theWidgetSizesAreTheOnesItDeclares() throws {
        let widget = try String(
            contentsOf: Self.root.appendingPathComponent("Widget/StatusWidget.swift"),
            encoding: .utf8
        )
        for family in ["systemSmall", "systemMedium", "systemLarge", "systemExtraLarge"] {
            #expect(widget.contains(family), "the Mac widget no longer offers .\(family)")
        }
        // Case-insensitively: the rule is that the README names four sizes, not
        // that the phrase sits mid-sentence. It began a section and the guard
        // refused it.
        #expect(try Self.readme().range(of: "all four sizes", options: .caseInsensitive) != nil,
                "the README no longer says the widget supports all four sizes")
    }

    /// The log is two hundred entries and fifty-six thousand words, and the
    /// README says the way to find something is to search the headings. There was
    /// nowhere they could be seen together until `tools/decisions-index`, and a
    /// generated file would have drifted from the log the first time one was
    /// appended without the other — which is the defect most of that log is
    /// about. So the tool reads the log and git each time, and this holds the
    /// README to describing a tool that is there and a count that is true.
    @Test func theReadmeSendsPeopleToAnIndexThatExists() throws {
        let root = Self.root
        #expect(FileManager.default.isExecutableFile(
            atPath: root.appendingPathComponent("tools/decisions-index").path),
            "tools/decisions-index is missing or not executable")

        let log = try String(
            contentsOf: root.appendingPathComponent("docs/DECISIONS.md"), encoding: .utf8)
        let headings = log.components(separatedBy: "\n## ").count - 1
        #expect(headings >= 150, "the log has \(headings) headings; the README says two hundred")
        #expect(try Self.readmeSays("decisions-index"),
                "the README no longer says how to see the headings together")
    }

    /// The phone widget's shapes, which the README counted wrongly: it said "the
    /// two accessory shapes a lock screen allows", and a lock screen allows
    /// three. The widget draws two of them on purpose — the inline one sits
    /// beside the clock with room for a few words, and would have to leave out
    /// either the figure or whose it is.
    ///
    /// A claim stated more strongly than the code supports, in the one document a
    /// developer reads before the code.
    @Test func thePhoneWidgetOffersTheShapesTheReadmeCounts() throws {
        let widget = try String(
            contentsOf: Self.root.appendingPathComponent("iOSWidget/PhoneWidget.swift"),
            encoding: .utf8)
        for family in [".systemSmall", ".systemMedium", ".systemLarge",
                       ".accessoryCircular", ".accessoryRectangular"] {
            #expect(widget.contains(family), "the phone widget no longer offers \(family)")
        }
        #expect(!widget.contains(".accessoryInline"), """
            the phone widget offers the inline shape now, and the README says it \
            does not and why
            """)
        #expect(try Self.readmeSays("two of the three"),
                "the README no longer says how many of the lock screen's shapes are drawn")
    }

    @Test func theLanguageCountIsTheNumberOfCatalogues() throws {
        let resources = Self.root
            .appendingPathComponent("Packages/Core/Sources/StatusUI/Resources")
        let catalogues = try FileManager.default
            .contentsOfDirectory(at: resources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "lproj" }
        #expect(catalogues.count == 10, "there are \(catalogues.count) catalogues, not ten")
        #expect(try Self.readmeSays("ten languages"),
                "the README no longer counts the languages")
    }

    /// The README is wrapped at 80 columns, so any phrase worth checking is
    /// liable to straddle a line break. Whitespace is collapsed before matching:
    /// the first attempt at this test failed on "moves by a / point", which is
    /// the file being tidy rather than the sentence being wrong.
    /// The README describes what `deploy.sh` checks, and it had stopped being
    /// true.
    ///
    /// It said the script "asks the live URL for a 200 before reporting
    /// success", which was accurate when it was written and has been wrong for
    /// a week: the deploy compares every file by digest, asserts the caching
    /// headers, and confirms the route and the restart policy would survive a
    /// reboot. Four checks were added one at a time and the sentence describing
    /// them never moved.
    ///
    /// Each pair below is a thing the script does and the words the README uses
    /// for it. Remove either and this fails.
    @Test func theReadmeDescribesWhatTheDeployActuallyChecks() throws {
        let readme = try Self.readme()
        let script = try String(
            contentsOf: Self.root.appendingPathComponent("site/deploy.sh"), encoding: .utf8
        )
        let checks = [
            ("shasum -a 256", "SHA-256"),
            ("Cache-Control", "Cache-Control"),
            ("kamal-proxy.state", "saved state"),
            ("RestartPolicy", "restart policy"),
            ("check-widths", "width check"),
        ]
        for (inScript, inReadme) in checks {
            #expect(script.contains(inScript),
                    "deploy.sh no longer does the \(inReadme) check the README describes")
            #expect(readme.range(of: inReadme, options: .caseInsensitive) != nil,
                    "the README does not mention the \(inReadme) check that deploy.sh does")
        }
    }

    /// The README counts the checks the commit hook runs.
    ///
    /// It listed four for weeks — a mail address, an account identifier, a
    /// credential shape, a home path — while the suite grew to eight. The four
    /// it omitted were the ones added after a rewrite of the whole history found
    /// what the first four had no opinion about, which makes them the four worth
    /// naming most.
    ///
    /// The count has earned this check twice since: a ninth check made it fail
    /// the day after it was written, and a tenth — the one that reads commit
    /// messages rather than files — made it fail again.
    @Test func theReadmeCountsTheChecksTheHookRuns() throws {
        let guards = try String(
            contentsOf: Self.root.appendingPathComponent(
                "Packages/Core/Tests/StatusUITests/NoPersonalDataTests.swift"
            ),
            encoding: .utf8
        )
        let count = guards.components(separatedBy: "@Test func").count - 1
        #expect(count == 10, "the personal-data suite has \(count) checks, not ten")
        #expect(try Self.readmeSays("ten checks"),
                "the README no longer counts the checks the hook runs")

        // The hook filters on the suite's name, and a filter matching nothing
        // exits zero — so the name in the hook has to be the name in the file.
        let hook = try String(
            contentsOf: Self.root.appendingPathComponent("tools/hooks/pre-commit"),
            encoding: .utf8
        )
        #expect(guards.contains("struct NoPersonalDataInTheRepository"),
                "the personal-data suite has been renamed")
        #expect(hook.contains("NoPersonalDataInTheRepository"),
                "the hook filters on a name the suite no longer has")
    }

    /// Everything the README points a reader at is there to be read.
    ///
    /// It said of the plans directory "see the note there" and there was no
    /// note — not a file, not a heading at the top of a plan. A reader following
    /// that instruction found three long documents opening with a banner
    /// addressed to a tool. A broken reference in the first document anybody
    /// reads is worse than no reference.
    /// Every repository path the README cites is a path that is there.
    ///
    /// This held a list of twelve paths and checked those files existed. It never
    /// read the README, so it passed with the README pointing at a document that
    /// does not exist — which is what it is named for — and would have passed
    /// with the README empty. Found by mutation: renaming a cited document
    /// produced no failure.
    ///
    /// Only tokens whose first segment is a real top-level entry here. The README
    /// also quotes `.plist` as a kind of file, `api.anthropic.com/api/…` as a URL,
    /// and `prev/` as a directory on the deploy host; none of those is a path in
    /// this repository and none should be looked for as one.
    @Test func everyRepositoryPathTheReadmeCitesIsThere() throws {
        let top = try Set(
            FileManager.default.contentsOfDirectory(atPath: Self.root.path)
        )
        let cited = Self.matches(#"`([^`\n]+)`"#, in: try Self.rawReadme())
            .filter { $0.contains("/") && !$0.contains(" ") }
            .filter { top.contains(String($0.prefix(while: { $0 != "/" }))) }

        guard cited.count >= 6 else {
            throw ScanIsLookingInTheWrongPlace(what: "cited path", found: cited.count, least: 6)
        }
        for path in Set(cited) {
            #expect(FileManager.default.fileExists(
                atPath: Self.root.appendingPathComponent(path).path),
                "the README cites \(path), which is not there")
        }
    }

    /// And the other direction: the documents somebody is meant to be sent to are
    /// still named. The plans' note is the one that had gone missing.
    @Test func theReadmeStillSendsPeopleToEachDocument() throws {
        let readme = try Self.rawReadme()
        for document in ["docs/DECISIONS.md", "docs/superpowers/specs/",
                         "docs/superpowers/plans/", "docs/design/",
                         "tools/add_strings.py"] {
            #expect(readme.contains(document), "the README no longer points at \(document)")
        }
        #expect(try Self.readmeSays("note in"), "the README no longer points at the plans' note")
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    /// Unsquashed: a path is not prose, and the squashing `readme()` does would
    /// join a path at a line break to the word after it.
    private static func rawReadme() throws -> String {
        try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
    }

    /// Takes the phrase, not the README: see `HowToAskADocument`.
    private static func readmeSays(_ phrase: String) throws -> Bool {
        try readme().says(phrase)
    }

    private static func readme() throws -> String {
        let text = try String(
            contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8
        )
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static var root: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
}
