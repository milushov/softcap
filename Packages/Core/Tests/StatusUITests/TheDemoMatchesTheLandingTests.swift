import Testing
import Foundation
@testable import Preferences

/// The demo shows the three accounts the landing page draws, and the two must
/// not drift apart.
///
/// They exist for one reason between them: somebody arriving at softcap.app sees
/// a window, downloads the app, and — having no subscription yet — is shown that
/// same window with the same numbers in it. App Review is the strictest reader
/// of that promise, having refused the build twice for seeing nothing at all.
/// A percentage edited on the page and left alone in the app breaks the only
/// thing this arrangement is for.
///
/// Both directions, like `TheLandingUsesTheAppsWords`: a figure changed on the
/// page without changing the source fails the first test, and the reverse fails
/// the second. Held by reading both files, because the demo lives in the app
/// target and this suite cannot import it.
@Suite struct TheDemoMatchesTheLanding {

    /// One limit window as both files must state it: what the page prints, and
    /// the `Track` the app declares.
    private struct Row {
        let address: String
        let plan: String
        /// What the meter shows, and the time beside it.
        let percent: Int
        let remaining: String
        /// The declaration in `DemoData`, whitespace collapsed.
        let track: String
    }

    private static let rows: [Row] = [
        Row(address: "alex@example.com", plan: "Codex · Plus", percent: 0, remaining: "—",
            track: "start: 0, resetsAfter: nil"),
        Row(address: "alex@example.com", plan: "Codex · Plus", percent: 39, remaining: "3d 22h",
            track: "start: 39, resetsAfter: 3 * 86400 + 22 * 3600"),
        Row(address: "sam@example.com", plan: "Claude · Max 20x", percent: 16, remaining: "2h 04m",
            track: "start: 16, resetsAfter: 2 * 3600 + 4 * 60"),
        Row(address: "sam@example.com", plan: "Claude · Max 20x", percent: 80, remaining: "3d 11h",
            track: "start: 80, resetsAfter: 3 * 86400 + 11 * 3600"),
        Row(address: "sam.k@example.com", plan: "Claude · Max 20x", percent: 100, remaining: "41m",
            track: "start: 100, resetsAfter: 41 * 60"),
        Row(address: "sam.k@example.com", plan: "Claude · Max 20x", percent: 55, remaining: "5d 16h",
            track: "start: 55, resetsAfter: 5 * 86400 + 16 * 3600"),
    ]

    @Test func thePageStillShowsTheseFigures() throws {
        let page = try Self.landing()
        for row in Self.rows {
            #expect(page.contains("<b>\(row.address)</b><i>\(row.plan)</i>"), """
                the landing no longer draws \(row.address) as \(row.plan) — \
                change App/DemoData.swift to match, or this table
                """)
            // The percentage and the time it belongs to, taken together: a
            // figure moved to the neighbouring row would otherwise still be
            // "on the page".
            let meter = ">\(row.percent)%</span><span class=\"t\">\(row.remaining)</span>"
            #expect(page.contains(meter), """
                the landing no longer pairs \(row.percent)% with \(row.remaining) \
                — the demo still does
                """)
        }
    }

    @Test func theAppStillDeclaresTheseFigures() throws {
        let source = try Self.demoData()
        for row in Self.rows {
            #expect(source.contains(row.address),
                    "the demo no longer shows \(row.address), which the landing draws")
            #expect(source.contains(row.track), """
                the demo no longer starts \(row.address) at \(row.percent)% with \
                \(row.remaining) left — the landing still shows that
                """)
        }
    }

    /// The addresses are `example.com` and nothing else. RFC 2606 reserves it
    /// for this, and the repository forbids a real mail address in a published
    /// artefact — which the store screenshots taken from these fixtures are.
    @Test func nobodysRealMailboxIsInTheSamples() throws {
        let source = try Self.demoData()
        let addresses = source.split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { $0.contains("@") && $0.contains(".") }
        let outside = addresses.filter { !$0.contains("example.com") }
        #expect(outside.isEmpty, "the samples name a mailbox outside example.com: \(outside)")
    }

    /// Everything that can put samples on screen also says they are samples.
    ///
    /// Four surfaces draw them and each was given the sentence separately, which
    /// is exactly the arrangement that loses one. A fifth screen added later
    /// without the label would show invented figures as though they were
    /// readings.
    @Test func everySurfaceThatShowsSamplesSaysSo() throws {
        let surfaces = [
            "App/PopoverView.swift",
            "App/Settings/StatisticsPane.swift",
            "App/Settings/AccountsPane.swift",
        ]
        for surface in surfaces {
            let source = try String(
                contentsOf: Self.root.appendingPathComponent(surface), encoding: .utf8)
            #expect(source.contains("Demo — sample data") || source.contains("Show sample data"),
                    "\(surface) can draw samples and no longer says that it is doing so")
        }
    }

    /// A sample is not a reading. The frame the demo draws must not be recorded,
    /// and must not be announced.
    ///
    /// One of the three accounts sits at a hundred per cent, and fed to the
    /// tracker it would deliver a notification within seconds of a first launch
    /// — about an account nobody has, on a machine nobody has signed in on.
    @Test func theDemoIsNeitherRecordedNorAnnounced() throws {
        let model = try String(contentsOf: Self.root.appendingPathComponent("App/AppModel.swift"),
                               encoding: .utf8)
        guard let frame = Self.block(after: "private func drawDemoFrame() {", in: model)
            .map(Self.code) else {
            Issue.record("drawDemoFrame is gone; this scan is looking in the wrong place")
            return
        }
        #expect(!frame.contains("tracker"),
                "the demo feeds the threshold tracker — a sample at 100% then posts a notification")
        #expect(!frame.contains("history.record") && !frame.contains("history.merge"), """
            the demo writes to the real history file — that overwrites a month of \
            somebody's own readings with invented ones
            """)
    }

    /// Preferences written before this mode existed decode to "off".
    ///
    /// Every installation of 0.1.22 carries a blob with no `demoMode` key and
    /// has accounts of its own. A plain `Bool` defaulting to true would have
    /// greeted all of them with three invented rows on the morning they updated.
    @Test func anUpgradeDoesNotTurnTheDemoOn() throws {
        var written = Preferences.defaults
        written.demoMode = nil
        let blob = try JSONEncoder().encode(written)
        let text = String(data: blob, encoding: .utf8) ?? ""
        #expect(!text.contains("demoMode"),
                "a nil demoMode is encoded, so this no longer reproduces an upgrade")

        let read = try JSONDecoder().decode(Preferences.self, from: blob)
        #expect(read.demoMode == nil, """
            preferences written without the key decode to a decision nobody made \
            — the app must resolve that itself, from whether there are accounts
            """)
    }

    @Test func aChoiceOnTheScreenSurvivesBeingSaved() throws {
        for choice in [true, false] {
            var written = Preferences.defaults
            written.demoMode = choice
            let read = try JSONDecoder().decode(
                Preferences.self, from: try JSONEncoder().encode(written))
            #expect(read.demoMode == choice, "the demo switch does not survive a save")
        }
    }

    // MARK: - Reading the files

    private static func landing() throws -> String {
        try String(contentsOf: root.appendingPathComponent("site/src/index.body.html"),
                   encoding: .utf8)
    }

    /// Whitespace collapsed, so a declaration wrapped across two lines still
    /// matches. Every guard in this suite has had to learn that separately.
    private static func demoData() throws -> String {
        let text = try String(contentsOf: root.appendingPathComponent("App/DemoData.swift"),
                              encoding: .utf8)
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The code with its prose taken off.
    ///
    /// Written after this suite failed on its own comment: the line saying the
    /// tracker is deliberately not fed contains the word `tracker`, and a scan
    /// that reads prose finds the thing the prose promises is absent.
    private static func code(_ source: String) -> String {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                guard let comment = line.range(of: "//") else { return line }
                return line[..<comment.lowerBound]
            }
            .joined(separator: "\n")
    }

    private static func block(after opening: String, in source: String) -> String? {
        guard let start = source.range(of: opening) else { return nil }
        let rest = source[start.upperBound...]
        guard let end = rest.range(of: "\n    }") else { return nil }
        return String(rest[..<end.lowerBound])
    }

    private static var root: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
}
