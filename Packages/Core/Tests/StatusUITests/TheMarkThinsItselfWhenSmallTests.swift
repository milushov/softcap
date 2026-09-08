import Testing
import Foundation

/// Below 40 px the mark drops its inner ring and thickens the outer one: two
/// concentric strokes a few pixels apart merge into a smudge rather than reading
/// as two rings.
///
/// That rule was written into `make-favicon.sh`, which bakes the `.ico` — and the
/// `.ico` is not what browsers use. The page declares `icon.svg` first, every
/// browser that can render an SVG favicon prefers it, and the SVG carried the
/// full two-ring mark at every size. The carefully thinned 16 px bitmap beside it
/// had never been shown to anybody.
///
/// The SVG now carries the rule itself, as a media query against its own
/// viewport. So the rule exists twice, in a shell script and in a stylesheet, and
/// this is what stops the two drifting.
@Suite struct TheMarkThinsItselfWhenSmall {

    @Test func theSvgCarriesTheRuleItself() throws {
        let icon = try Self.icon()
        let rule = try Self.mediaBlock(in: icon)

        #expect(rule.contains(".inner"), "the media query does not drop the inner ring")
        #expect(rule.contains("display: none") || rule.contains("display:none"),
                "the inner ring is styled at small sizes but not hidden")
        #expect(rule.contains(".outer"), "the media query does not touch the outer ring")

        // A class that is not on anything styles nothing, and the query would
        // pass this test while changing the drawing not at all.
        #expect(icon.components(separatedBy: "class=\"outer\"").count - 1 == 2,
                "the two outer circles are not both marked")
        #expect(icon.components(separatedBy: "class=\"inner\"").count - 1 == 2,
                "the two inner circles are not both marked")
    }

    /// One rule, two files: the shell script that bakes the bitmap and the
    /// stylesheet inside the vector. They have to agree on where "small" starts
    /// and on how much thicker the ring gets.
    @Test func theScriptAndTheSvgAgreeOnWhatSmallMeans() throws {
        let script = try Self.script()

        guard let scriptThreshold = Self.firstGroup(#"-lt (\d+)"#, in: script).flatMap(Int.init) else {
            Issue.record("make-favicon.sh no longer tests the size against a threshold")
            return
        }
        guard let svgThreshold = Self
            .firstGroup(#"max-width:\s*(\d+)px"#, in: try Self.icon()).flatMap(Int.init) else {
            Issue.record("icon.svg no longer names the width its rule applies below")
            return
        }
        // The script asks `< 40`; a media query is inclusive, so it asks `<= 39`.
        #expect(svgThreshold == scriptThreshold - 1, """
            the script thins below \(scriptThreshold) and the vector below \
            \(svgThreshold + 1) — one of them was changed alone
            """)

        guard let scriptWidth = Self
            // The second half of the replacement, not the first: the script says
            // `.replace('stroke-width="5"', 'stroke-width="7"')`, and matching the
            // nearest number found the width being replaced away.
            .firstGroup(#"replace\('stroke-width="\d+"', 'stroke-width="(\d+)"'\)"#, in: script)
            .flatMap(Int.init) else {
            Issue.record("make-favicon.sh no longer names the thickened stroke")
            return
        }
        guard let svgWidth = Self
            .firstGroup(#"\.outer\s*\{[^}]*stroke-width:\s*(\d+)"#, in: try Self.icon())
            .flatMap(Int.init) else {
            Issue.record("icon.svg no longer names the thickened stroke")
            return
        }
        #expect(scriptWidth == svgWidth, """
            the bitmap thickens the ring to \(scriptWidth) and the vector to \(svgWidth)
            """)
    }

    /// The third copy. The page draws the same mark inline in its header, at a
    /// size below the threshold, and it did not follow the rule — so the tab and
    /// the header, inches apart on one screen, showed one ring and two.
    ///
    /// That divergence was introduced by fixing the favicon, which is the reason
    /// this check exists rather than the rule being left in two places.
    @Test func theHeaderMarkFollowsTheRuleToo() throws {
        let page = try Self.read("site/index.html", least: 20_000)
        let mark = try Self.headerMark(in: page)

        guard let drawnAt = Self.firstGroup(#"<svg width="(\d+)""#, in: mark).flatMap(Int.init),
              let threshold = Self.firstGroup(#"max-width:\s*(\d+)px"#, in: try Self.icon())
                .flatMap(Int.init)
        else {
            Issue.record("the header mark or the rule no longer names a size")
            return
        }
        // If the header ever grows past the threshold this rule is wrong for it,
        // and the failure should say so rather than the mark quietly thinning.
        #expect(drawnAt <= threshold, """
            the header mark is drawn at \(drawnAt)px, at or above the \(threshold + 1)px the mark thins below — it should be showing both rings, and the page's .brand rule should go
            """)

        #expect(mark.components(separatedBy: "outer").count - 1 == 2,
                "the header's two outer circles are not both marked")
        #expect(mark.components(separatedBy: "inner").count - 1 == 2,
                "the header's two inner circles are not both marked")

        let hides = Self.firstGroup(#"\.brand \.inner\{([^}]*)\}"#, in: page) ?? ""
        #expect(hides.contains("display:none") || hides.contains("display: none"),
                "the page does not drop the header mark's inner ring")

        guard let headerWidth = Self
            .firstGroup(#"\.brand \.outer\{[^}]*stroke-width:\s*(\d+)"#, in: page)
            .flatMap(Int.init),
              let iconWidth = Self
            .firstGroup(#"\.outer\s*\{[^}]*stroke-width:\s*(\d+)"#, in: try Self.icon())
            .flatMap(Int.init)
        else {
            Issue.record("one of the two files no longer names the thickened stroke")
            return
        }
        #expect(headerWidth == iconWidth, """
            the header thickens the ring to \(headerWidth) and the icon to \(iconWidth)
            """)
    }

    /// The fourth copy, and the one furthest away: `tools/make_icons.swift` draws
    /// this same mark for the Dock, the menu bar and the phone, in CoreGraphics
    /// rather than SVG. It carries the threshold and both fill fractions as its
    /// own constants, and nothing joined them to the vector's.
    ///
    /// Not the stroke weight. The generator thickens the small ring to 0.135 of
    /// the side and the vector to 7/64 — different pipelines, different
    /// antialiasing, each tuned by eye against what it produces. The threshold
    /// and the fills are what carry meaning: where the mark stops showing two
    /// rings, and how full they are drawn.
    @Test func theAppsIconGeneratorAgreesWithTheVector() throws {
        let generator = try Self.read("tools/make_icons.swift", least: 2_000)
        let icon = try Self.icon()

        guard let cutoff = Self.firstGroup(#"innerRingCutoff = (\d+)"#, in: generator)
            .flatMap(Int.init),
              let queried = Self.firstGroup(#"max-width:\s*(\d+)px"#, in: icon).flatMap(Int.init)
        else {
            Issue.record("one of the two files no longer names the size the mark thins below")
            return
        }
        // The generator asks `< 40`; a media query is inclusive, so it asks `<= 39`.
        #expect(queried == cutoff - 1, """
            the app thins below \(cutoff) and the vector below \(queried + 1)
            """)

        for (name, constant, radius) in [("weekly", "weeklyFill", 21.0),
                                         ("session", "sessionFill", 11.5)] {
            guard let declared = Self.firstGroup("\(constant) = ([0-9.]+)", in: generator)
                .flatMap(Double.init) else {
                Issue.record("the generator no longer declares \(constant)")
                continue
            }
            guard let drawn = Self.dashFraction(radius: radius, in: icon) else {
                Issue.record("the vector has no \(name) ring at radius \(radius)")
                continue
            }
            #expect(abs(declared - drawn) < 0.005, """
                the app draws the \(name) ring \(declared) full and the vector \
                \(String(format: "%.3f", drawn))
                """)
        }
    }

    /// How much of the circle at that radius the dash covers.
    private static func dashFraction(radius: Double, in svg: String) -> Double? {
        let r = radius == radius.rounded() ? String(Int(radius)) : String(radius)
        let pattern = "r=\"" + r + "\"[^>]*stroke-dasharray=\"([0-9.]+) "
        guard let dash = firstGroup(pattern, in: svg).flatMap(Double.init) else { return nil }
        return dash / (2 * Double.pi * radius)
    }

    /// The header's inline `<svg>`, from its opening tag to its close. Searching
    /// the page as a whole would find the window mock's circles too.
    ///
    /// Found through `class="brand"`, not through the width: locating it by the
    /// size made changing the size fail the *search* instead of the size check,
    /// so the one assertion about how large it is drawn could never be reached.
    private static func headerMark(in page: String) throws -> String {
        guard let brand = page.range(of: "class=\"brand\""),
              let start = page.range(of: "<svg", range: brand.upperBound..<page.endIndex),
              let end = page.range(of: "</svg>", range: start.upperBound..<page.endIndex)
        else { throw ScanIsLookingInTheWrongPlace(what: "header mark", found: 0, least: 1) }
        return String(page[start.lowerBound..<end.upperBound])
    }

    // MARK: -

    private static func mediaBlock(in css: String) throws -> String {
        guard let start = css.range(of: "@media"),
              let open = css.range(of: "{", range: start.upperBound..<css.endIndex)
        else { throw ScanIsLookingInTheWrongPlace(what: "media query", found: 0, least: 1) }
        var depth = 0
        var index = open.lowerBound
        while index < css.endIndex {
            if css[index] == "{" { depth += 1 }
            if css[index] == "}" {
                depth -= 1
                if depth == 0 { return String(css[open.upperBound..<index]) }
            }
            index = css.index(after: index)
        }
        throw ScanIsLookingInTheWrongPlace(what: "media query (unclosed)", found: 0, least: 1)
    }

    private static func firstGroup(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func icon() throws -> String {
        try read("site/icon.svg", least: 400)
    }

    private static func script() throws -> String {
        try read("site/make-favicon.sh", least: 800)
    }

    private static func read(_ path: String, least: Int) throws -> String {
        let text = try String(
            contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
        guard text.count >= least else {
            throw ScanIsLookingInTheWrongPlace(what: path, found: text.count, least: least)
        }
        return text
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
