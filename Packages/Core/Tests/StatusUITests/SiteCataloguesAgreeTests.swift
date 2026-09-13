import Testing
import Foundation

/// The site is generated: one shell, eight bodies, ten string catalogues.
///
/// The app's catalogues have had a parity floor since the day the second
/// language arrived, and it has caught real drift. The site's catalogues get
/// the same floor here — plus the checks a generated site newly makes
/// possible: that the committed pages are exactly what the sources render,
/// that every page names its siblings in every language, and that the Arabic
/// pages actually read right to left rather than merely existing.
@Suite struct SiteCataloguesAgree {

    // MARK: keys

    @Test func everyCatalogueHasTheSameKeys() throws {
        let catalogues = try Self.catalogues()
        guard let english = catalogues["en"] else {
            Issue.record("strings/en.json is missing — there is no source catalogue")
            return
        }
        for (lang, catalogue) in catalogues where lang != "en" {
            let missing = Set(english.keys).subtracting(catalogue.keys).sorted()
            let extra = Set(catalogue.keys).subtracting(english.keys).sorted()
            #expect(missing.isEmpty && extra.isEmpty, """
                \(lang).json disagrees with en.json — missing \(missing.prefix(6)), \
                extra \(extra.prefix(6))
                """)
            for (key, value) in english {
                guard let translated = catalogue[key] else { continue }
                #expect(Self.tokens(in: value) == Self.tokens(in: translated), """
                    \(lang).json changes the {{…}} tokens inside \(key) — a token \
                    lost in translation is a hole in the rendered page
                    """)
            }
        }
    }

    // MARK: freshness

    /// `build.py --check` renders into a temporary directory and compares
    /// byte for byte. Run from here as well as from the pre-commit hook,
    /// because CI runs the tests and not the hook.
    @Test func theBuiltPagesAreFresh() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "site/build.py", "--check"]
        process.currentDirectoryURL = Self.repositoryRoot()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
        #expect(process.terminationStatus == 0, """
            the committed pages are not what the sources render:
            \(output)
            """)
    }

    // MARK: the cluster

    /// Every page lists every rendered language plus x-default, and every
    /// address it lists is a file that exists. A cluster that names a page
    /// which is not there sends a search engine — and a reader — into a 404
    /// with this site's own signature on it.
    ///
    /// Counted from what was built rather than from the catalogues on disk:
    /// this asks whether the pages agree with each other, and the separate
    /// freshness test asks whether they agree with their sources. Conflating
    /// the two made a half-finished translation look like a broken cluster.
    @Test func everyPageListsAllItsSiblings() throws {
        let expected = try Self.builtLanguages().count + 1  // + x-default
        for page in try Self.builtPages() {
            let html = try String(contentsOf: Self.site(page), encoding: .utf8)
            // The picker's rows carry hreflang too; the head's cluster is the
            // <link> form, so count those alone.
            let links = html.components(separatedBy: "<link rel=\"alternate\" hreflang=\"").count - 1
            #expect(links == expected, """
                \(page) lists \(links) alternates, and \(expected) languages \
                (with x-default) are rendered
                """)
            // And the picker's own links say what they lead to. This began as
            // `count >= links` over every hreflang on the page, which compared
            // a set with a subset of itself and could not fail — a check in the
            // shape of a check. A picker row without `lang`/`hreflang` hands a
            // screen reader the wrong pronunciation for the one control a
            // reader who cannot read this page is looking for.
            for row in Self.matches(#"<a class="lang-row"[^>]*>"#, in: html, whole: true) {
                #expect(row.contains("lang=") && row.contains("hreflang="), """
                    \(page) has a picker row that does not name its language: \(row)
                    """)
            }
            for address in Self.matches(#"<link rel="alternate" hreflang="[^"]+" href="https://softcap\.app/([^"]*)""#,
                                        in: html) {
                let target = address.isEmpty ? "index.html" : address + "index.html"
                #expect(FileManager.default.fileExists(atPath: Self.site(target).path), """
                    \(page) points hreflang at /\(address) and \(target) does not exist
                    """)
            }
        }
    }

    // MARK: direction

    /// A Latin token ending in `+` comes apart in a right-to-left paragraph.
    ///
    /// `macOS 14+` rendered as `+macOS 14` on the Arabic landing: the plus is
    /// a neutral character, so the bidi algorithm resolves it against the
    /// paragraph rather than against the token it belongs to, and moves it to
    /// the far side of the phrase. Verified in a headless render before and
    /// after — `<bdi dir="ltr">` around the token fixes it and nothing else
    /// does. Percentages are deliberately not covered: `80%` keeps its sign
    /// beside its number and merely follows the paragraph's direction, which
    /// is how Arabic writes it.
    @Test func rightToLeftCataloguesIsolateLatinTokensEndingInAPlus() throws {
        for (lang, catalogue) in try Self.catalogues() where Self.rightToLeft.contains(lang) {
            for (key, value) in catalogue {
                // Every isolated span removed first, so what remains is the
                // text that is actually exposed to the paragraph's direction.
                // Asking only whether the value contains a `<bdi>` somewhere
                // passed a sentence that isolated one token and left another
                // bare — which is the case this exists to catch.
                let exposed = value.replacingOccurrences(
                    of: #"<bdi[^>]*>.*?</bdi>"#, with: "",
                    options: [.regularExpression])
                #expect(Self.matches(#"[0-9]\+"#, in: exposed).isEmpty, """
                    \(lang).json \(key) leaves a + after a number outside a <bdi> — \
                    right-to-left rendering moves that + to the other end of the \
                    phrase: \(value.prefix(60))
                    """)
            }
        }
    }

    @Test func theArabicPagesReadRightToLeft() throws {
        guard try Self.builtLanguages().contains("ar") else { return }
        let html = try String(contentsOf: Self.site("ar/index.html"), encoding: .utf8)
        #expect(html.contains(#"<html lang="ar" dir="rtl">"#),
                "the Arabic landing does not declare dir=\"rtl\"")
        #expect(html.contains(#"class="stage" dir="ltr""#), """
            the window mock lost its left-to-right island — it depicts the
            English app and must not mirror
            """)
    }

    // MARK: the picker

    /// Every page offers every rendered language by its own name.
    ///
    /// The names are spelled here as well as in build.py on purpose: if one
    /// side changes, somebody meant it twice. Only the languages actually
    /// built are required — the ten arrived one file at a time, and a picker
    /// offering a page that does not exist yet is the worse failure.
    @Test func thePickerNamesEveryLanguageOnEveryPage() throws {
        let native = ["en": "English", "ru": "Русский", "es": "Español",
                      "fr": "Français", "ar": "العربية", "bn": "বাংলা",
                      "hi": "हिन्दी", "id": "Bahasa Indonesia",
                      "pt-BR": "Português (Brasil)", "zh-Hans": "中文（简体）"]
        let built = try Self.builtLanguages()
        for page in try Self.builtPages() {
            let html = try String(contentsOf: Self.site(page), encoding: .utf8)
            if built.count < 2 {
                #expect(!html.contains("<details class=\"lang\">"),
                        "\(page) offers a picker with nothing to pick")
                continue
            }
            for lang in built {
                guard let name = native[lang] else {
                    Issue.record("\(lang) is built and has no name in this test")
                    continue
                }
                #expect(html.contains(name), "\(page) does not offer \(name)")
            }
        }
    }

    // MARK: plumbing

    /// Kept beside `RTL` in build.py rather than read from it: two spellings
    /// of the same short fact, so changing the set is a deliberate act twice.
    private static let rightToLeft: Set<String> = ["ar"]

    private static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // …/StatusUITests
            .deletingLastPathComponent()      // …/Tests
            .deletingLastPathComponent()      // …/Core
            .deletingLastPathComponent()      // …/Packages
            .deletingLastPathComponent()      // repository root
    }

    private static func site(_ path: String) -> URL {
        repositoryRoot().appendingPathComponent("site").appendingPathComponent(path)
    }

    private static func catalogues() throws -> [String: [String: String]] {
        let directory = site("strings")
        var out: [String: [String: String]] = [:]
        for file in try FileManager.default.contentsOfDirectory(atPath: directory.path)
        where file.hasSuffix(".json") {
            let data = try Data(contentsOf: directory.appendingPathComponent(file))
            out[String(file.dropLast(5))] =
                try JSONDecoder().decode([String: String].self, from: data)
        }
        return out
    }

    /// The languages actually present in the built tree, read from the
    /// manifest: a page at the root is English, and one under a known
    /// language directory belongs to that language. Page directories like
    /// `limits/` are not language directories and are ignored by name.
    private static func builtLanguages() throws -> [String] {
        let directories = ["ru", "es", "fr", "ar", "bn", "hi", "id",
                           "pt-br", "zh-hans"]
        let spelling = ["pt-br": "pt-BR", "zh-hans": "zh-Hans"]
        var found: Set<String> = []
        for page in try builtPages() {
            let first = page.split(separator: "/").first.map(String.init) ?? ""
            if directories.contains(first) {
                found.insert(spelling[first] ?? first)
            } else {
                found.insert("en")
            }
        }
        return found.sorted()
    }

    private static func builtPages() throws -> [String] {
        let manifest = try String(contentsOf: site("manifest.txt"), encoding: .utf8)
        let pages = manifest.split(separator: "\n").map(String.init)
            .filter { $0.hasSuffix("index.html") }
        #expect(!pages.isEmpty, "the manifest lists no pages at all")
        return pages
    }

    private static func tokens(in value: String) -> [String] {
        matches(#"\{\{[^}]*\}\}"#, in: value, whole: true).sorted()
    }

    private static func matches(_ pattern: String, in text: String,
                                whole: Bool = false) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            let index = whole || match.numberOfRanges < 2 ? 0 : 1
            guard let r = Range(match.range(at: index), in: text) else { return nil }
            return String(text[r])
        }
    }
}
