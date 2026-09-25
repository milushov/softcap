import Testing
import Foundation
@testable import ProviderKit
@testable import Preferences
@testable import StatusUI

/// The landing page recreates the app's window in CSS rather than showing a
/// screenshot: sharp at any density, carrying no personal data, and editable.
/// The cost is a second copy of the interface, which drifts from the first one
/// unless something notices.
///
/// This is that something. It checks both directions — a label the page shows
/// must exist in the app's catalogue, and a label listed here must still be on
/// the page. Renaming a key in the app fails the first; quietly dropping a row
/// from the mock fails the second.
///
/// It cannot check that the *layout* still matches, only the words. That is the
/// part a person has to look at.
@Suite struct TheLandingUsesTheAppsWords {

    /// What the mock displays, paired with the catalogue key it comes from.
    /// They differ where the app formats a value into the string.
    private static let shown: [(onPage: String, key: String)] = [
        ("Subscription limits", "Subscription limits"),
        ("Refresh",             "Refresh"),
        ("Settings…",           "Settings…"),
        ("Quit",                "Quit"),
        ("5h",                  "5h"),
        ("week",                "week"),
        ("Data from",           "Data from %@"),
    ]

    @Test func everyLabelOnThePageIsAKeyInTheCatalogue() throws {
        let catalogue = try Self.englishKeys()
        let missing = Self.shown
            .map(\.key)
            .filter { !catalogue.contains($0) }
        #expect(missing.isEmpty, """
            the landing shows words the app no longer has: \(missing.sorted()) \
            — rename them in site/index.html or put the keys back
            """)
    }

    @Test func everyLabelListedHereIsStillOnThePage() throws {
        let mock = try Self.mockText()
        let absent = Self.shown
            .map(\.onPage)
            .filter { !mock.contains($0) }
        #expect(absent.isEmpty, """
            listed as shown on the landing but not found there: \(absent.sorted()) \
            — update this list if the mock changed on purpose
            """)
    }

    /// The window's title is the one place the app's own name would show through
    /// a rename. It did survive one.
    @Test func theMockDoesNotCarryAFormerNameOfTheApp() throws {
        let page = try String(contentsOf: Self.landingPage, encoding: .utf8)
        // Both spellings. The rename swept "StatusChecker" everywhere and left
        // "Status Checker" — with a space — in a mock-up's own heading, where
        // every search for the closed-up form went straight past it.
        for spelling in ["StatusChecker", "Status Checker"] {
            #expect(!page.contains(spelling), "the landing still says \(spelling)")
        }
    }

    /// The window lists accounts least loaded first, so the one you can go and
    /// work in is at the top. The mock is a picture of that window, so its rows
    /// have to be in the order the window would put them — otherwise the page
    /// illustrates a screen the app never draws.
    @Test func theMockListsAccountsLeastLoadedFirst() throws {
        let peaks = try Self.rowPeaks()
        #expect(peaks.count >= 2, "found \(peaks.count) rows in the mock")
        #expect(peaks == peaks.sorted(), """
            the mock's rows run \(peaks) — the window orders them least loaded first, so a picture of it cannot run any other way
            """)
    }

    /// The status item is a template image: the system tints it, white on a dark
    /// menu bar and black on a light one. It carries no colour of its own and
    /// none of the load scale — so the strip on the page must not either.
    ///
    /// The app icon in the header is a different thing and is green, correctly.
    /// Only the strip is checked.
    @Test func theStatusItemInTheMockIsMonochrome() throws {
        let strip = try Self.menuBarMarkup()
        let coloured = ["#34c759", "#e5c04b", "#e8963c", "#e8574a"]
            .filter { strip.localizedCaseInsensitiveContains($0) }
        #expect(coloured.isEmpty, """
            the mock's status item is drawn in \(coloured) — the real one is a template image and has no colour of its own
            """)
    }

    /// One page, one set of accounts. The window and the chart illustrate the
    /// same three, so a name in the chart's legend that is not a row in the
    /// window means the two pictures are of different machines.
    @Test func theChartAndTheWindowShowTheSameAccounts() throws {
        let page = try String(contentsOf: Self.landingPage, encoding: .utf8)

        let inWindow = Set(Self.matches(#"<b>([a-z.]+)@example\.com</b>"#, in: page))
        let inLegend = Set(Self.matches(#"</i>([a-z.]+)</span>"#, in: page))

        #expect(!inWindow.isEmpty, "no accounts found in the window mock")
        #expect(!inLegend.isEmpty, "no names found in the chart legend")
        #expect(inLegend == inWindow, """
            the chart's legend names \(inLegend.sorted()) and the window lists \
            \(inWindow.sorted()) — one page, one set of accounts
            """)
    }

    // MARK: - reading

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }


    /// Just the menu bar strip, which is the first line of the mock through to
    /// the line that closes it.
    private static func menuBarMarkup() throws -> String {
        let lines = try String(contentsOf: landingPage, encoding: .utf8)
            .components(separatedBy: "\n")
        guard let first = lines.firstIndex(where: { $0.contains("class=\"menubar\"") }),
              let last = lines[first...].firstIndex(where: { $0.contains("class=\"desk\"") })
        else {
            Issue.record("the menu bar strip was not found in site/index.html")
            return ""
        }
        return lines[first..<last].joined(separator: "\n")
    }


    /// The highest percentage in each row of the mock, top to bottom. That is
    /// what `orderedForDisplay` sorts on.
    ///
    /// Read out of the mock's own markup rather than the whole file: splitting
    /// the page leaves a last piece that runs to the end of it, and the chart's
    /// axis labels are `>100%<` and `>75%<` — the last row's peak would come
    /// from a gridline.
    private static func rowPeaks() throws -> [Int] {
        let rows = try mockMarkup().components(separatedBy: "<div class=\"row\">").dropFirst()
        return rows.compactMap { Self.percentages(in: String($0)).max() }
    }

    private static func percentages(in text: String) -> [Int] {
        let pattern = try? NSRegularExpression(pattern: ">(\\d+)%<")
        let range = NSRange(text.startIndex..., in: text)
        return pattern?.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).flatMap { Int(text[$0]) }
        } ?? []
    }


    private static func englishKeys() throws -> Set<String> {
        let url = repositoryRoot
            .appendingPathComponent("Packages/Core/Sources/StatusUI/Resources/en.lproj")
            .appendingPathComponent("Localizable.strings")
        let text = try String(contentsOf: url, encoding: .utf8)
        let pattern = try NSRegularExpression(pattern: "^\"((?:[^\"\\\\]|\\\\.)*)\"\\s*=",
                                              options: .anchorsMatchLines)
        let range = NSRange(text.startIndex..., in: text)
        return Set(pattern.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        })
    }

    private static var landingPage: URL {
        repositoryRoot.appendingPathComponent("site/index.html")
    }

    /// The words the mock displays, with the markup taken out.
    ///
    /// Only the mock, not the whole file: `Refresh` appears in the prose further
    /// down as "Refreshing it can rotate…", and searching the page as a whole
    /// found that instead — so renaming the button changed nothing and the test
    /// passed. Checked by making exactly that edit and watching it not fail.
    ///
    /// Taken line by line rather than by character ranges, which is duller and
    /// cannot end up with a lower bound above an upper one.
    private static func mockText() throws -> String {
        try mockMarkup()
            .replacingOccurrences(of: "<svg[^>]*>.*?</svg>", with: " ",
                                  options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&hellip;", with: "…")
    }

    /// The mock's markup, from the menu bar strip to the window's footer.
    private static func mockMarkup() throws -> String {
        let lines = try String(contentsOf: landingPage, encoding: .utf8)
            .components(separatedBy: "\n")
        // The closing line is searched for *after* the opening one: `win-foot`
        // also names a rule in the stylesheet further up the file, and taking
        // the first match anywhere put the end before the start.
        guard let first = lines.firstIndex(where: { $0.contains("class=\"menubar\"") }),
              let last = lines[first...].firstIndex(where: { $0.contains("class=\"win-foot\"") })
        else {
            Issue.record("the mock's markup was not found in site/index.html")
            return ""
        }
        return lines[first...last].joined(separator: "\n")
    }

    /// The page now draws the app twice: the window, and the small widget on the
    /// desktop behind it. The widget shows the busiest account — that is what
    /// `compact` in `LimitsWidgetView` picks — so its three values are not free.
    /// They are the largest percentage in the window mock, the account carrying
    /// it, and that meter's remaining time.
    ///
    /// Without this, editing a number in one picture leaves the other asserting
    /// something the first one contradicts, a few hundred pixels away.
    @Test func theWidgetOnTheDesktopShowsTheBusiestAccountInTheWindow() throws {
        let page = try String(contentsOf: Self.landingPage, encoding: .utf8)

        // Each row of the window mock: a name and the percentages under it.
        var busiest: (name: String, percent: Int, left: String)?
        for row in page.components(separatedBy: #"<div class="row">"#).dropFirst() {
            guard let name = Self.firstGroup(#"<b>([^<]+)</b>"#, in: row) else { continue }
            for meter in Self.allGroups(#"class="v"[^>]*>(\d+)%</span><span class="t">([^<]*)</span>"#,
                                        in: row, groups: 2) {
                guard let percent = Int(meter[0]) else { continue }
                if busiest == nil || percent > busiest!.percent {
                    busiest = (name, percent, meter[1])
                }
            }
        }
        guard let busiest else {
            throw ScanIsLookingInTheWrongPlace(what: "window mock row", found: 0, least: 3)
        }

        let shown = Self.firstGroup(#"<span class="big">(\d+)%</span>"#, in: page)
        #expect(shown == String(busiest.percent), """
            the widget on the page shows \(shown ?? "nothing") where the window's busiest row is \(busiest.percent)% — the small widget shows the busiest
            """)

        let who = Self.firstGroup(#"<span class="who2">([^<]+)</span>"#, in: page)
        #expect(who == busiest.name, """
            the widget names \(who ?? "nobody") and the busiest row is \(busiest.name)
            """)

        let left = Self.firstGroup(#"<span class="left">([^<]+)</span>"#, in: page)
        #expect(left == busiest.left, """
            the widget says \(left ?? "nothing") left and that row says \(busiest.left)
            """)

        // And the app still picks the busiest, which is what makes the three
        // values above the right ones to demand.
        let widget = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent("Widget/LimitsWidgetView.swift"),
            encoding: .utf8)
        let picksTheBusiest = widget.contains("max { $0.peakPercent < $1.peakPercent }")
        #expect(picksTheBusiest, """
            the small widget no longer picks the account with the highest percentage, so the page's desktop widget is drawing something else
            """)
    }

    private static func firstGroup(_ pattern: String, in text: String) -> String? {
        allGroups(pattern, in: text, groups: 1).first?.first
    }

    /// Every match, each as its capture groups.
    private static func allGroups(_ pattern: String, in text: String, groups: Int) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m in
            let captured = (1...groups).compactMap { Range(m.range(at: $0), in: text).map { String(text[$0]) } }
            return captured.count == groups ? captured : nil
        }
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)      // …/Packages/Core/Tests/StatusUITests/<file>.swift
            .deletingLastPathComponent()      // …/Tests/StatusUITests
            .deletingLastPathComponent()      // …/Tests
            .deletingLastPathComponent()      // …/Core
            .deletingLastPathComponent()      // …/Packages
            .deletingLastPathComponent()      // repository root
    }
}

/// The page and the README must agree about whether you can have the app.
///
/// They did not. The page said "in development", which was true — no release has
/// ever been published. The README offered a download link, which resolved to a
/// 404: the release workflow exists and runs on every push, and every run had
/// failed in three seconds without anyone noticing.
///
/// This is checkable without the network, because the two files have to say the
/// same thing whichever is true.
@Suite struct TheReadmeAndThePageAgreeOnAvailability {

    /// The page says what it is three times: the note under the headline, the
    /// footer, and the `description` in the structured data. Nothing required
    /// them to agree, and two of them are places nobody re-reads — a release
    /// would update the sentence a person sees and leave a search result saying
    /// the software is unfinished, or the reverse.
    ///
    /// Found by mutation: changing the visible mentions left the JSON-LD saying
    /// it, and the page went on being consistent by accident.
    @Test func thePageAgreesWithItselfAboutBeingFinished() throws {
        let page = try Self.landing()
        guard let script = page.range(of: "application/ld+json"),
              let close = page.range(of: "</script>", range: script.upperBound..<page.endIndex)
        else {
            Issue.record("the page has no structured data to compare against")
            return
        }
        let structured = String(page[script.upperBound..<close.lowerBound])
        let visible = page.replacingCharacters(
            in: script.lowerBound..<close.upperBound, with: " ")

        #expect(visible.says("in development") == structured.says("in development"), """
            the page and its structured data disagree about whether Softcap is finished — one of them was updated and the other was not, and the one nobody re-reads is the one a search result quotes
            """)
    }

    @Test func onlyOneOfThemCanBeRight() throws {
        let page = try Self.landing()
        let readme = try Self.readme()

        let inDevelopment = page.says("in development")
        let offersADownload = readme.contains("releases/latest/download")

        #expect(inDevelopment != offersADownload, """
            the landing says \(inDevelopment ? "in development" : "it has shipped") \
            while the README \(offersADownload ? "offers a download" : "offers none") — \
            when a release is published the page should stop saying it is in development
            """)
    }

    /// The page offers the appearances the app offers, and no others.
    ///
    /// `Appearance` is system, light and dark. The page had been dark only, with
    /// `color-scheme: dark` stating that it followed nobody. Offering a choice
    /// here means offering the same three — a page that let you pick a palette
    /// the app cannot would be describing different software.
    @Test func theAppearancesAreTheOnesTheAppOffers() throws {
        let page = try Self.landing()
        #expect(Appearance.allCases.count == 3,
                "the app now has \(Appearance.allCases.count) appearances; the page offers three")
        for appearance in Appearance.allCases {
            let id = appearance == .system ? "t-system" : "t-\(appearance.rawValue)"
            #expect(page.contains("id=\"\(id)\""),
                    "the page has no control for \(appearance.rawValue)")
            // And the label, which is the whole of the control a reader can reach:
            // the radio is a pixel wide at zero opacity, so an input without its
            // label is an appearance the page offers to nobody. Checking only the
            // input passed with the third label deleted.
            #expect(page.contains("for=\"\(id)\""), """
                the page has no label for \(appearance.rawValue) — the radio is hidden, so without one the appearance cannot be chosen
                """)
        }
        // The switch is still CSS, and inline script is still refused. The policy
        // grants `script-src 'self'` for one file of this origin's own; code
        // written into the document is not covered by it and would be blocked at
        // load — in production, in a console nobody is watching. Refused here,
        // where the reason is next to the rule.
        #expect(!page.contains("<script>") && !page.contains("javascript:"),
                "the page carries an inline script, which `script-src 'self'` blocks")
        #expect(page.contains("html:has(#t-light:checked)")
                && page.contains("html:has(#t-dark:checked)"),
                "the appearance switch no longer sets color-scheme from the checked radio")
    }

    /// What the page tells a crawler has to be what it tells a person.
    ///
    /// The structured data carried an `Offer` at price zero, which states that
    /// the software is available at no cost. It is not available at all: the
    /// repository is private, no release exists, and the page two lines above
    /// says so. A claim nobody reads is still a claim — and it was made in the
    /// one part of the page a human never looks at, by the same hand that spent
    /// a week removing claims of exactly that shape from the prose.
    @Test func theStructuredDataClaimsNoMoreThanThePage() throws {
        let page = try Self.landing()
        guard page.contains("application/ld+json") else { return }

        if page.says("in development") {
            #expect(!page.contains("\"offers\""), """
                the structured data offers the software while the page says it is \
                in development — an Offer is a statement that it can be had
                """)
            #expect(!page.contains("\"availability\""),
                    "the structured data states an availability the page denies")
        }
        // Whatever it says about itself, it has to be readable. A block that
        // does not parse is worth less than no block.
        #expect(page.contains("\"@type\":\"SoftwareApplication\""),
                "the structured data no longer describes an application")

        // The platforms it names are ones the package is actually built for, and
        // it may not name one the page does not offer. Nothing else on the page
        // states a version, so this is the one place that figure could go
        // quietly wrong — and since 20 September the iPhone app is not offered
        // at all, which a structured-data block is the easiest place to forget.
        #expect(page.contains("macOS 14"), """
            the structured data does not name the platform the package is built \
            for: Package.swift says macOS 14
            """)
        #expect(!page.contains("iOS 17"), """
            the page names iOS 17 again — the iPhone app is not offered, and \
            structured data is read by machines that will not notice
            """)
    }

    /// The mark in the header is the app's icon, not a themed drawing of it.
    ///
    /// When the page gained light and dark palettes the logo was tokenised along
    /// with everything else, and in light mode it came out with a pale plate and
    /// a dark inner ring — a different mark from `icon.svg`, shown beside a
    /// browser tab displaying the real one. An icon is the one thing on a page
    /// that must not follow the page: it looks the same on any wallpaper, in the
    /// Dock, and in the tab.
    @Test func theMarkIsTheIconAndDoesNotFollowTheTheme() throws {
        let page = try Self.landing()
        let icon = try String(
            contentsOf: Self.root.appendingPathComponent("site/icon.svg"), encoding: .utf8
        )
        for colour in Self.colours(in: icon) {
            #expect(page.contains(colour),
                    "the header mark does not use \(colour), which icon.svg does")
        }
        for rule in ["plate", "hush", "arc", "ink"] {
            guard let line = page.components(separatedBy: "\n")
                .first(where: { $0.hasPrefix(".brand .\(rule){") })
            else {
                Issue.record("no rule for the mark's \(rule)")
                continue
            }
            #expect(!line.contains("var(--"), """
                the mark's \(rule) is painted from a theme token — it would change \
                with the palette, and the app's icon does not
                """)
        }
    }

    /// Every `#rrggbb` in a file, lowercased, without duplicates.
    private static func colours(in svg: String) -> Set<String> {
        let pattern = "#[0-9a-fA-F]{6}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(svg.startIndex..., in: svg)
        return Set(regex.matches(in: svg, range: range).compactMap {
            Range($0.range, in: svg).map { svg[$0].lowercased() }
        })
    }

    /// The chart's identity colours are the app's, in the app's order.
    ///
    /// `AccountPalette` hands a colour out by an account's position in the
    /// sorted list of ids, and an id begins with the provider — so `claude/…`
    /// always precedes `codex/…`, and Codex is coloured last however many Claude
    /// accounts there are. The drawing follows that rule exactly, which is not
    /// something anybody would reproduce by eye, and nothing was checking it.
    @Test func theChartUsesTheAppsColoursInTheAppsOrder() throws {
        let page = try Self.landing()

        for (index, hex) in AccountPalette.hexes.enumerated() {
            let token = "--id-\(index + 1):"
            guard page.contains(token) else { continue }
            #expect(page.contains(hex), """
                the page defines \(token) but never \(hex), which is \
                AccountPalette.hexes[\(index)]
                """)
        }

        // The lines carry the colours the legend promises. Checked separately
        // because everything below reads the legend, and the legend is a row of
        // dots: pointing `.a1 .line` at `--id-2` draws the line for one account
        // in another's colour, leaves every assertion here true, and makes the
        // key beneath the drawing a lie about the drawing.
        let lines = Self.matches(#"\.a(\d) \.line,\.a\d \.glow,\.a\d \.reset\{stroke:var\(--id-(\d)\)\}"#,
                                 in: page, groups: 2)
        #expect(lines.count >= 3, "found \(lines.count) chart lines to check")
        for line in lines {
            #expect(line[0] == line[1], """
                the chart draws line \(line[0]) in identity colour \(line[1]) — the legend names them by the same number, so the key belongs to a different line than the one it sits under
                """)
        }

        // name → the identity slot the legend gives it
        var slot: [String: Int] = [:]
        for match in Self.matches(#"var\(--id-(\d)\)"></i>([a-z.]+)</span>"#, in: page, groups: 2) {
            slot[match[1]] = Int(match[0]) ?? 0
        }
        #expect(slot.count >= 2, "found \(slot.count) legend entries to check")

        // The slots used are the first few, with nothing skipped: the app hands
        // them out by position and never leaves a gap.
        #expect(Set(slot.values) == Set(1...slot.count),
                "the legend uses slots \(slot.values.sorted()) — the app would use 1…\(slot.count)")

        // name → provider, from the window mock above the chart
        var provider: [String: String] = [:]
        for match in Self.matches(#"<b>([a-z.]+)@example\.com</b><i>(Claude|Codex)"#,
                                  in: page, groups: 2) {
            provider[match[0]] = match[1]
        }
        let claude = slot.filter { provider[$0.key] == "Claude" }.map(\.value)
        let codex  = slot.filter { provider[$0.key] == "Codex" }.map(\.value)
        #expect(!claude.isEmpty && !codex.isEmpty, "the mock no longer shows both services")
        #expect((codex.min() ?? 0) > (claude.max() ?? 0), """
            the drawing colours Codex before Claude — an account id begins with \
            its provider, "claude/" sorts before "codex/", and the palette is \
            handed out in that order
            """)
    }

    private static func matches(
        _ pattern: String, in text: String, groups: Int
    ) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (1...groups).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
        }
    }

    /// The services the page says are coming are the ones the app lists.
    ///
    /// `ProviderID` has seven cases; two are read today and five appear in
    /// Settings under "Later". The page names those four in its own words —
    /// "GitHub Copilot", "Gemini CLI", "GLM Coding Plan" — which is right for a
    /// reader and means the two lists agree by memory alone.
    ///
    /// Which is why this exists, and it has now caught the thing it was written
    /// for: a sixth case was added to the enum and to Settings, and the page
    /// went on naming three until this failed. The count below is deliberate —
    /// it fails on the *next* one too, so somebody has to look at the page
    /// rather than at a list that grew by itself.
    @Test func thePageNamesTheServicesTheAppHasNotBuiltYet() throws {
        let page = try Self.landing()
        let built: Set<ProviderID> = [.claude, .codex]
        let planned = ProviderID.allCases.filter { !built.contains($0) }

        #expect(planned.count == 5,
                "the app now plans \(planned.count) more services; the page names five")
        // The question is asked before `#expect` sees it, and that is the point.
        //
        // `#expect(page.contains(x))` makes `page` an operand, and a failure
        // prints every operand — so one failing assertion here wrote 330 KB of
        // rendered HTML, and the sentence explaining what was wrong was
        // somewhere inside it. Measured, twice, while adding a provider: this
        // is the assertion that fires every time one is added, so it is the one
        // whose failure has to be readable. A `Bool` prints as `false`.
        for provider in planned {
            let named = page.contains(provider.title)
            #expect(named,
                    "the page does not name \(provider.title), which the app lists as coming")
        }
        for provider in built {
            let named = page.contains(provider.title)
            #expect(named,
                    "the page does not name \(provider.title), which the app reads today")
        }
    }

    /// Nothing anybody reads still calls the app by its old name.
    ///
    /// The rename replaced "StatusChecker" throughout. "Status Checker", spaced,
    /// survived in the heading of a design mock-up — the one document a reader is
    /// pointed at to see what the window was meant to look like — because every
    /// search since has looked for the closed-up form.
    ///
    /// `StatusChecker-accounts` is the keychain service, kept through the rename
    /// on purpose so that nothing already stored is lost, and is allowed.
    @Test func nothingAReaderOpensCarriesTheOldName() throws {
        var offenders: [String] = []
        for url in try Self.readableFiles() {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (number, line) in text.components(separatedBy: "\n").enumerated() {
                let stripped = line.replacingOccurrences(of: "StatusChecker-accounts", with: "")
                for spelling in ["StatusChecker", "Status Checker"]
                where stripped.contains(spelling) {
                    offenders.append("\(url.lastPathComponent):\(number + 1)")
                }
            }
        }
        #expect(offenders.isEmpty, """
            the old name is still readable at \(Array(Set(offenders)).sorted()) — only the keychain service keeps it, and only because renaming it would lose what is stored under it
            """)
    }

    /// The documents and pages a person opens: the mock-ups, the landing and the
    /// README. Not the decision log or the plans, which are a record of when the
    /// name was still the old one and would be falsified by changing it.
    private static func readableFiles() throws -> [URL] {
        ["docs/design/menu-window-variants.html",
         "docs/design/settings-screen.html",
         "site/index.html",
         "site/og-template.html",
         "README.md"].map { root.appendingPathComponent($0) }
    }

    private static func landing() throws -> String {
        try file("site/index.html")
    }

    private static func file(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private static func readme() throws -> String {
        try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
    }

    private static var root: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
}

/// The one script this site serves, and the four files that have to agree about
/// it.
///
/// `site/clock.js` puts the real time into the hero's mock, because the menu bar
/// in that picture read "Mon 2:41 AM" on every visit from the day it was drawn —
/// the single detail a reader could hold against the corner of their own screen,
/// and the one the picture was always wrong about.
///
/// Three of the four ways it can break are silent, and all of them look
/// identical from outside: a menu bar reading 2:41 AM, exactly as before.
@Suite struct TheLandingsOneScriptIsWiredUp {

    /// The page loads it, the mock carries the places it writes, the manifest
    /// lists it — `deploy.sh` copies `--files-from` that file, so a name missing
    /// there never reaches the host — and the served policy allows it to run.
    @Test func theHeroClockIsLoadedAndAllowedToRun() throws {
        let page = try Self.landing()
        #expect(page.contains("<script src=\"/clock.js\" defer></script>"),
                "the landing does not load /clock.js, so the mock's menu bar is frozen again")
        for anchor in ["menubar", "window", "stale"] {
            #expect(page.contains("data-clock=\"\(anchor)\""),
                    "the mock has no data-clock=\"\(anchor)\" for the script to write")
        }

        let script = try Self.file("site/clock.js")
        for anchor in ["menubar", "window", "stale"] {
            #expect(script.contains("data-clock=\"\(anchor)\""),
                    "clock.js does not look for data-clock=\"\(anchor)\"")
        }

        #expect(try Self.file("site/manifest.txt").contains("clock.js"),
                "clock.js is not in the manifest, so the deploy would never copy it")
        #expect(try Self.file("site/Caddyfile").contains("script-src 'self'"),
                "the served policy forbids the page's own script, so the clock runs nowhere but here")
    }

    private static func file(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private static func landing() throws -> String { try file("site/index.html") }

    private static var root: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
}
