import Testing
import Foundation

/// The link preview and the page have to say the same thing.
///
/// `og.png` is rendered from `og-template.html`, and `deploy.sh` re-renders it
/// when the template is newer. Nothing connected either to the page: edit the
/// headline in `index.html` and the preview keeps the old one, silently, because
/// nobody looks at their own link previews. The decision log recorded that gap
/// when the template was introduced and left it open.
///
/// This closes it from the other end. The template must repeat what the page
/// says, so changing the page forces changing the template — which makes the
/// template newer than the image, which makes the deploy re-render it. The chain
/// completes itself.
@Suite struct ThePreviewMatchesThePage {

    @Test func theHeadlineIsTheSame() throws {
        let headline = try Self.headlineOfThePage()
        #expect(!headline.isEmpty, "the page has no headline to compare")
        let preview = try Self.squashed(Self.template())
        #expect(preview.contains(headline), """
            the preview does not carry the page's headline "\(headline)" — \
            og-template.html has drifted, and og.png is rendered from it
            """)
    }

    /// The same three accounts, with the same figures. The preview is a smaller
    /// drawing of the same window; two windows disagreeing about what they show
    /// is the kind of thing only a stranger notices.
    @Test func theMockShowsTheSameAccounts() throws {
        let page = try Self.squashed(Self.landing())
        let preview = try Self.squashed(Self.template())
        for account in ["alex@example.com", "sam@example.com", "sam.k@example.com"] {
            #expect(page.contains(account), "the page no longer shows \(account)")
            #expect(preview.contains(account), "the preview no longer shows \(account)")
        }
        for figure in ["Codex · Plus", "Claude · Max 20x"] {
            #expect(preview.contains(figure), "the preview no longer shows \(figure)")
        }
    }

    /// The status the page gives itself. When a release is published and the page
    /// stops saying "in development", the preview cannot keep saying it.
    @Test func theStatusIsTheSame() throws {
        // Bound to Bools first: the expectation prints its sub-expressions, and
        // these two are whole documents. See `HowToAskADocument`.
        let pageSaysIt = try Self.squashed(Self.landing()).says("in development")
        let previewSaysIt = try Self.squashed(Self.template()).says("in development")
        #expect(pageSaysIt == previewSaysIt, """
            the page and its preview disagree about whether Softcap is in development
            """)
    }

    /// Every bar is as long as the number beside it says.
    ///
    /// A drawing of a window is worth exactly as much as its agreement with the
    /// window. A bar at 80% drawn two thirds along is a picture of software that
    /// does not exist, and nobody reads a mock-up with a ruler.
    ///
    /// Zero is the one exception, and it is the app's own: `AccountRow` sizes a
    /// bar `max(2, width * percent / 100)`, so an unused window still shows a
    /// stub rather than an empty track. Both drawings do the same.
    @Test func everyBarIsAsLongAsItsLabel() throws {
        for (name, html) in [("index.html", try Self.landing()),
                             ("og-template.html", try Self.template())] {
            let bars = Self.bars(in: html)
            #expect(bars.count == 6, "\(name): expected six bars, found \(bars.count)")
            for bar in bars {
                if bar.label == 0 {
                    #expect(bar.width > 0 && bar.width <= 3, """
                        \(name): a bar at 0% is drawn \(bar.width)% wide — the app shows a small stub, not an empty track and not a real bar
                        """)
                } else {
                    #expect(abs(bar.width - Double(bar.label)) < 1.01, """
                        \(name): a bar labelled \(bar.label)% is drawn \(bar.width)% wide
                        """)
                }
            }
        }
    }

    /// The width of each fill and the number printed after it.
    private static func bars(in html: String) -> [(width: Double, label: Int)] {
        let pattern = #"<i style="width:([0-9.]+)%[^"]*"></i></span><span class="v"[^>]*>([0-9]+)%"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let w = Range(match.range(at: 1), in: html),
                  let l = Range(match.range(at: 2), in: html),
                  let width = Double(html[w]), let label = Int(html[l])
            else { return nil }
            return (width, label)
        }
    }

    /// The preview is painted in the page's dark palette, and only in that.
    ///
    /// `og.png` is one image, so it cannot follow a reader's appearance — it is
    /// the dark page, drawn once. That is fine while the two use the same
    /// values, and nothing was checking that they did: the page's colours moved
    /// into `light-dark()` pairs the same week, and if a dark value had been
    /// adjusted on the way through, the preview would have kept the old one
    /// without a word.
    ///
    /// The mark's own colours are allowed too — an icon does not follow a
    /// palette, which is the subject of an entry of its own.
    @Test func thePreviewUsesThePagesDarkPalette() throws {
        let page = try Self.landing()
        let template = try Self.template()

        let dark = Self.darkPalette(of: page)
        #expect(dark.count > 10, "found only \(dark.count) colours in the page's dark palette")

        let icon = try Self.hexes(in: String(
            contentsOf: Self.root.appendingPathComponent("site/icon.svg"), encoding: .utf8
        ))
        let allowed = dark.union(icon)

        for colour in try Self.hexes(in: template) {
            #expect(allowed.contains(colour), """
                the preview paints with \(colour), which is neither in the page's \
                dark palette nor in the mark — og.png would not look like the page
                """)
        }
    }

    /// The second half of every `--x: light-dark(light, dark)` in the page.
    private static func darkPalette(of page: String) -> Set<String> {
        let pattern = #"light-dark\(\s*(?:#[0-9a-fA-F]{6}|rgba\([^)]*\))\s*,\s*(#[0-9a-fA-F]{6})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(page.startIndex..., in: page)
        return Set(regex.matches(in: page, range: range).compactMap { match in
            Range(match.range(at: 1), in: page).map { page[$0].lowercased() }
        })
    }

    private static func hexes(in text: String) throws -> Set<String> {
        let regex = try NSRegularExpression(pattern: "#[0-9a-fA-F]{6}")
        let range = NSRange(text.startIndex..., in: text)
        return Set(regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { text[$0].lowercased() }
        })
    }

    // MARK: - reading the two files

    /// The text of the page's `<h1>`, with tags and runs of whitespace removed.
    private static func headlineOfThePage() throws -> String {
        let page = try landing()
        guard let open = page.range(of: "<h1"),
              let gt = page.range(of: ">", range: open.upperBound..<page.endIndex),
              let close = page.range(of: "</h1>", range: gt.upperBound..<page.endIndex)
        else { return "" }

        // The decorative mark comes out before the words are compared. It is
        // `aria-hidden` and it is an ornament: a cycling glyph with the name of
        // whichever service it is showing, which nobody reads as part of the
        // sentence and which a still picture 1200 points wide has no way to be.
        //
        // It cost nothing while it held only glyphs — `squash` drops tags, and
        // there was no text inside them — and started counting the moment the
        // names were added, which turned the headline into "Claude Code OpenAI
        // Codex GitHub Copilot Every subscription limit…" and failed here. That
        // is this check working: it is the words of the headline it holds the
        // preview to, and the mark is not one of them.
        let headline = String(page[gt.upperBound..<close.lowerBound])
            .replacingOccurrences(
                of: "<span class=\"cycle\".*?</span></span>",
                with: "", options: [.regularExpression])
        return squash(headline)
    }

    /// Tags out, entities that matter turned back into spaces, whitespace
    /// collapsed — so a line break between two files does not read as a
    /// difference.
    private static func squash(_ html: String) -> String {
        var text = html.replacingOccurrences(
            of: "<[^>]+>", with: " ", options: .regularExpression
        )
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func squashed(_ html: String) -> String { squash(html) }

    private static func landing() throws -> String {
        try String(contentsOf: root.appendingPathComponent("site/index.html"), encoding: .utf8)
    }

    private static func template() throws -> String {
        try String(contentsOf: root.appendingPathComponent("site/og-template.html"), encoding: .utf8)
    }

    private static var root: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }

    /// The headline is two halves, and the second is grey. On the page it is also
    /// its own line, set that way on purpose: sized in `ch` it otherwise breaks
    /// wherever the font runs out of room, and the rhythm the two halves are
    /// written for goes with it.
    ///
    /// The template never learned that. Its `h1 em` had no `display:block`, so
    /// every shared link showed "limit," and "on one screen." running together on
    /// one line in two different colours — the design inverted, on the one image
    /// most people see before they see anything else. The page carried the fix
    /// and a comment explaining it; nothing connected the two files.
    @Test func theSecondHalfOfTheHeadlineIsItsOwnLineInBoth() throws {
        for (name, css) in [("site/index.html", try Self.landing()),
                            ("site/og-template.html", try Self.template())] {
            guard let rule = Self.rule(for: "h1 em", in: css) else {
                Issue.record("\(name) has no rule for the headline's second half")
                continue
            }
            let ownLine = rule.contains("display:block")
            #expect(ownLine, """
                \(name) lets the headline's second half share a line with the first. Both halves are one sentence in two colours; broken anywhere but between them it reads as neither.
                """)
        }
    }

    /// The body of the first `selector{…}` rule, declarations only.
    private static func rule(for selector: String, in css: String) -> String? {
        guard let start = css.range(of: selector + "{"),
              let end = css.range(of: "}", range: start.upperBound..<css.endIndex)
        else { return nil }
        return String(css[start.upperBound..<end.lowerBound])
    }
}
