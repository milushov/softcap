import Testing
import Foundation

/// The mark in the headline draws a service and, on hover, names it. The two
/// lists are written by hand in one element, and they have to stay the same
/// length and say things this app has heard of.
///
/// This exists because the mark went stale in silence. Every other surface that
/// mentions a service has something holding it: the hosts it reaches, the
/// product names it writes, the count the page promises, the catalogues. Two
/// services were added to the app while the mark went on drawing three, and
/// nothing failed — the mark was the one place with no check at all.
///
/// What it does *not* hold is which services belong in the mark. That is a
/// question about what the page says rather than about whether it contradicts
/// itself, and it is open. What is checked here is the contradiction: a glyph
/// with no name, a name with no glyph, or a name for a service that does not
/// exist.
@Suite struct TheHeadlineMarkNamesWhatItDraws {

    @Test func everyGlyphHasAName() throws {
        let mark = try Self.mark()
        let glyphs = Self.count(of: "<svg", in: mark)
        let names = Self.names(in: mark)

        #expect(glyphs > 0, "the headline mark draws nothing; this check is then vacuous")
        #expect(glyphs == names.count, """
            the mark draws \(glyphs) services and names \(names.count) of them: \
            \(names). A glyph with no name says nothing on hover, and a name \
            with no glyph never shows at all.
            """)
    }

    /// The names are the app's own, not free text. A mark naming something this
    /// app cannot read is the page promising a service that does not exist.
    @Test func everyNameIsOneTheAppKnows() throws {
        let known = Set(try Self.productNames())
        #expect(known.count >= 4, "the product names could not be read; this check proves nothing")

        for name in try Self.names(in: Self.mark()) {
            #expect(known.contains(name), """
                the headline mark names "\(name)", which is not a product this app \
                reads. The names it may use are \(known.sorted()).
                """)
        }
    }

    /// Each name is timed to its own glyph, so the one showing is the one that
    /// matches. A name without its delay sits under whichever glyph happens to
    /// be up — and reads as the app calling Codex "Claude Code".
    @Test func eachNameIsTimedToItsOwnGlyph() throws {
        let style = try Self.stylesheet()
        let names = try Self.names(in: Self.mark())

        for position in 2...max(2, names.count) {
            #expect(style.contains(".cycle .tip:nth-of-type(\(position)){animation-delay:"), """
                the name at position \(position) has no delay of its own, so it \
                shows under whichever glyph is up rather than under its own
                """)
        }
    }

    /// Hovering stops the cycle. A label on something that keeps moving is a
    /// label you finish reading about the next thing.
    @Test func hoveringHoldsTheMarkStill() throws {
        let style = try Self.stylesheet()
        #expect(style.contains(".cycle:hover svg,.cycle:hover .tip{animation-play-state:paused}"), """
            the mark no longer stops while its name is read, so the name changes \
            under the pointer
            """)
    }

    // MARK: - reading the page's own sources

    private static func mark() throws -> String {
        let body = try String(
            contentsOf: repositoryRoot.appendingPathComponent("site/src/index.body.html"),
            encoding: .utf8)
        guard let start = body.range(of: "<span class=\"cycle\""),
              let end = body.range(of: "</span>{{index.hero_title}}", range: start.upperBound..<body.endIndex)
        else {
            throw MarkIsNotWhereItWas()
        }
        return String(body[start.lowerBound..<end.lowerBound])
    }

    private static func names(in mark: String) -> [String] {
        Self.matches(#"<span class="tip">([^<]+)</span>"#, in: mark)
    }

    private static func productNames() throws -> [String] {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("App/ProviderNaming.swift"),
            encoding: .utf8)
        return Self.matches(#"case \.[a-z]+:\s*"([^"]+)""#, in: source)
    }

    private static func stylesheet() throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent("site/src/shell.html"),
            encoding: .utf8)
    }

    private static func count(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    private struct MarkIsNotWhereItWas: Error {}

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
