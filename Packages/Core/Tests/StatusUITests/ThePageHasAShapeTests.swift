import Testing
import Foundation

/// The page's structure for anybody not looking at it: the landmark to jump to,
/// headings that step one level at a time, and no drawing announced as an
/// unnamed image.
///
/// None of it is visible. Adding `<main>` changed the render by zero pixels —
/// checked by rendering before and after and comparing the two images — which is
/// exactly why nothing would notice it being lost again in a restructure.
@Suite struct ThePageHasAShape {

    @Test func thereIsOneMainAndTheContentIsInside() throws {
        let body = try Self.body()

        #expect(body.components(separatedBy: "<main").count - 1 == 1,
                "the page does not have exactly one main landmark")

        guard let open = body.range(of: "<main>"), let close = body.range(of: "</main>") else {
            throw ScanIsLookingInTheWrongPlace(what: "main landmark", found: 0, least: 1)
        }
        let inside = String(body[open.upperBound..<close.lowerBound])
        let before = String(body[body.startIndex..<open.lowerBound])
        let after = String(body[close.upperBound...])

        #expect(inside.contains("<h1"), "the headline is outside the main landmark")
        #expect(inside.components(separatedBy: "<section").count - 1 >= 5,
                "the sections are not inside the main landmark")
        #expect(before.contains("<header"), "the header is not before the main landmark")
        #expect(after.contains("<footer"), "the footer is not after the main landmark")
    }

    /// A jump from `h1` to `h3` reads, to somebody moving by headings, as a level
    /// that was skipped rather than a section that was shallow.
    @Test func theHeadingsStepOneLevelAtATime() throws {
        let levels = Self.matches(#"<h([1-6])\b"#, in: try Self.body()).compactMap(Int.init)
        guard levels.count >= 8 else {
            throw ScanIsLookingInTheWrongPlace(what: "heading", found: levels.count, least: 8)
        }
        #expect(levels.first == 1, "the page does not open with its h1")
        for (previous, next) in zip(levels, levels.dropFirst()) where next > previous + 1 {
            Issue.record("the page steps from h\(previous) to h\(next), skipping a level")
        }
    }

    /// Every drawing is either named, hidden, or inside something that is one of
    /// those — and the last of those three is the whole difficulty.
    ///
    /// Counted twice before by looking only at the `<svg>` tag itself, which
    /// reported eight defects both times and none of them real: the menu bar
    /// strip is `aria-hidden`, and the window and widget mocks are `role="img"`
    /// with a sentence each, so everything drawn inside them is already spoken
    /// for. This walks the ancestors, which is the only way to answer it.
    @Test func noDrawingIsAnnouncedWithoutAName() throws {
        let body = try Self.body()
        var stack: [String] = []          // attributes of each open element
        var covered = 0, marked = 0, bare: [String] = []

        for tag in Self.matches(#"<(/?[a-zA-Z][^>]*)>"#, in: body) {
            if tag.hasPrefix("/") {
                if !stack.isEmpty { stack.removeLast() }
                continue
            }
            let name = tag.prefix { !$0.isWhitespace && $0 != "/" }
            let speaksForChildren = { (attributes: String) in
                attributes.contains("aria-hidden=\"true\"") || attributes.contains("role=\"img\"")
            }
            if name == "svg" {
                if speaksForChildren(tag) { marked += 1 }
                else if stack.contains(where: speaksForChildren) { covered += 1 }
                else { bare.append(String(tag.prefix(60))) }
            }
            // Self-closing and void tags never open a scope.
            if !tag.hasSuffix("/"), !Self.void.contains(String(name)) { stack.append(tag) }
        }

        guard marked + covered + bare.count >= 8 else {
            throw ScanIsLookingInTheWrongPlace(
                what: "drawing", found: marked + covered + bare.count, least: 8)
        }
        #expect(covered > 0, """
            no drawing was found inside a hidden or named ancestor, which is how \
            most of them are covered — the walk is not tracking ancestors
            """)
        #expect(bare.isEmpty, """
            a screen reader announces these as unnamed images: \
            \(bare.joined(separator: " / "))
            """)
    }

    /// Paper is white and a browser's print dialog has background graphics off by
    /// default, so a page read in the dark palette would put near-white text on
    /// it. Every colour here is a `light-dark()` pair following `color-scheme`,
    /// which is why one line flips the palette — and why the two `:checked`
    /// rules have to be beaten as well, or the reader's own choice survives onto
    /// the page.
    @Test func thePagePrintsInInkRatherThanInTheReadersPalette() throws {
        let page = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent("site/index.html"),
            encoding: .utf8)

        guard let block = Self.firstGroup(#"(?s)@media print \{(.*?)\n\}"#, in: page) else {
            Issue.record("the page has no rules for paper")
            return
        }
        #expect(block.contains("color-scheme: light") || block.contains("color-scheme:light"),
                "printing does not pin the light palette, so a dark page prints near-white")
        for chosen in ["#t-light:checked", "#t-dark:checked"] {
            #expect(block.contains(chosen), """
                printing does not override html:has(\(chosen)), so a reader who \
                picked an appearance takes it onto the paper
                """)
        }
    }

    private static func firstGroup(_ pattern: String, in text: String) -> String? {
        matches(pattern, in: text).first
    }

    // MARK: -

    private static let void: Set<String> = [
        "br", "img", "input", "meta", "link", "hr", "source", "area", "col",
        "path", "circle", "rect", "line", "use", "stop", "polygon", "polyline", "ellipse",
    ]

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    /// The body with `<style>` and `<script>` taken out: the stylesheet names
    /// `header`, `section` and `footer` in its selectors, and a scan that reads
    /// it finds landmarks that are only rules.
    private static func body() throws -> String {
        let page = try String(
            contentsOf: repositoryRoot.appendingPathComponent("site/index.html"), encoding: .utf8)
        guard let start = page.range(of: "<body") else {
            throw ScanIsLookingInTheWrongPlace(what: "body", found: 0, least: 1)
        }
        var body = String(page[start.lowerBound...])
        for tag in ["style", "script"] {
            guard let regex = try? NSRegularExpression(
                pattern: "<\(tag)[^>]*>.*?</\(tag)>",
                options: [.dotMatchesLineSeparators, .caseInsensitive]) else { continue }
            body = regex.stringByReplacingMatches(
                in: body, range: NSRange(body.startIndex..., in: body), withTemplate: " ")
        }
        return body
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
