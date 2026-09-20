import Testing
import Foundation
@testable import StatusUI

/// The App Store listing lives in `store/metadata` as plain files, and Apple
/// counts the characters in every one of them.
///
/// A name of 31 characters is not refused when it is written — it is refused
/// when the listing is sent, which is after the screenshots have been made and
/// while somebody is waiting to submit. The limits are cheap to check here and
/// expensive to meet the other way round. They are Apple's, from App Store
/// Connect's own fields: 30, 30, 100, 4000, 170, 4000.
///
/// The keyword rules are not Apple's but ASO's, and the reasoning is in
/// `store/README.md`: the field is a hundred characters of index, a word spent
/// twice buys nothing, and a word already in the name or the subtitle is
/// already indexed.
@Suite struct StoreListingFitsTheStore {

    /// App Store Connect has no Bengali, so the app speaks one language more
    /// than the listing does. Everything else the app speaks has a listing, and
    /// Spanish has two — Latin America falls back to English rather than to
    /// Spain, which is a listing nobody would have noticed missing.
    private static let expected: Set<String> = [
        "en-US", "ru", "es-ES", "es-MX", "fr-FR", "pt-BR", "hi", "id", "ar-SA", "zh-Hans",
    ]

    private static let limits = [
        "name": 30, "subtitle": 30, "keywords": 100,
        "description": 4000, "promotional_text": 170, "whats_new": 4000,
    ]

    @Test func everyLanguageTheAppSpeaksHasAListing() throws {
        let found = try Self.locales()
        #expect(found == Self.expected, """
            the listing covers \(found.sorted()) — it should cover \
            \(Self.expected.sorted()); see store/README.md for why Bengali is \
            not among them
            """)

        // The app's own languages, minus the one App Store Connect cannot take,
        // compared by language alone: the app says `ar` and `es`, the store
        // `ar-SA` and `es-ES`, and `pt-BR` is `pt-BR` on both sides.
        func language(_ code: String) -> String { String(code.split(separator: "-")[0]) }
        let spoken = Set(AppLanguage.allCases.map(\.rawValue)).subtracting(["system", "bn"])
        let listed = Set(found.map(language))
        for code in spoken where !listed.contains(language(code)) {
            Issue.record("the app speaks \(code) and the store listing does not")
        }
    }

    @Test func nothingIsLongerThanTheStoreAllows() throws {
        for locale in try Self.locales().sorted() {
            for (field, limit) in Self.limits.sorted(by: { $0.key < $1.key }) {
                let text = try Self.read(field, in: locale)
                // UTF-16, which is how Apple counts: a Devanagari or Arabic
                // listing is shorter in characters than in the units the field
                // is measured in, and the difference is where a listing that
                // looks safe is refused.
                #expect(text.utf16.count <= limit, """
                    \(locale)/\(field).txt is \(text.utf16.count) of \(limit) allowed
                    """)
                #expect(!text.isEmpty, "\(locale)/\(field).txt is empty")
            }
        }
    }

    @Test func theKeywordFieldSpendsItsHundredCharactersOnce() throws {
        for locale in try Self.locales().sorted() {
            let keywords = try Self.read("keywords", in: locale)
            #expect(!keywords.contains(", "), """
                \(locale): a space after a comma costs a character of index and \
                buys nothing — Apple splits on the comma
                """)

            let words = keywords.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces).lowercased()
            }
            #expect(Set(words).count == words.count,
                    "\(locale): a keyword is written twice — \(words.sorted())")

            // Apple indexes the name, the subtitle and this field together, so a
            // word already in one of the first two is a word this field is
            // paying for a second time.
            let titles = try (Self.read("name", in: locale) + " "
                              + Self.read("subtitle", in: locale)).lowercased()
            let alreadyIndexed = titles.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
            for word in words where alreadyIndexed.contains(word) {
                Issue.record("\(locale): \"\(word)\" is in the name or subtitle already")
            }
        }
    }

    /// Both companies are named in the disclaimer, in every language, because
    /// the listing carries their trademarks in its own name and keywords.
    @Test func everyListingSaysWhoItIsNot() throws {
        for locale in try Self.locales().sorted() {
            let description = try Self.read("description", in: locale)
            #expect(description.contains("Anthropic") && description.contains("OpenAI"), """
                \(locale)/description.txt does not name both companies — the \
                listing uses their marks and has to say it is neither of them
                """)
        }
    }

    /// The three links Apple shows beside the listing — the app's page, its
    /// support page, its privacy policy — are sent in the reader's language,
    /// and the languages are spelled differently on each side: App Store
    /// Connect says `pt-BR` and `zh-Hans`, the site's directories are `pt-br`
    /// and `zh-hans`. A wrong spelling is a 404 on the button a reviewer
    /// presses, so the map in the push tool is read here and checked against
    /// the pages that exist.
    @Test func theListingLinksIntoTheRightLanguage() throws {
        let tool = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent("tools/push_store_metadata.py"),
            encoding: .utf8)
        guard let start = tool.range(of: "SITE_LANGUAGE = {"),
              let end = tool.range(of: "}", range: start.upperBound..<tool.endIndex) else {
            Issue.record("push_store_metadata.py no longer carries a SITE_LANGUAGE map")
            return
        }

        var mapped: Set<String> = []
        for pair in tool[start.upperBound..<end.lowerBound].split(separator: ",") {
            let halves = pair.split(separator: ":")
            guard halves.count == 2 else { continue }
            let locale = halves[0].trimmingCharacters(in: CharacterSet(charactersIn: " \n\"'"))
            let directory = halves[1].trimmingCharacters(in: CharacterSet(charactersIn: " \n\"'/"))
            mapped.insert(locale)
            for page in ["support", "privacy"] {
                let path = directory.isEmpty ? "site/\(page)/index.html"
                                             : "site/\(directory)/\(page)/index.html"
                #expect(FileManager.default.fileExists(
                    atPath: Self.repositoryRoot.appendingPathComponent(path).path), """
                    \(locale) is sent to /\(directory) and \(path) is not there
                    """)
            }
        }
        #expect(mapped == Self.expected, """
            the link map covers \(mapped.sorted()), the listing \(Self.expected.sorted())
            """)
    }

    /// Each of the five screenshots has a background of its own and a one-word
    /// headline of its own, and the three files that know this — the screen
    /// list in the generator, the palette in the renderer, the headlines — are
    /// held to one set of names. The first store set had one background under
    /// all five, which nothing here would have caught; the second had five
    /// palettes keyed by name, which a renamed screen would fall out of and
    /// come back as a refused run rather than a wrong picture.
    @Test func everyScreenshotHasItsOwnBackgroundAndHeadline() throws {
        let generator = try Self.tool("tools/store_screenshots.py")
        let renderer = try Self.tool("tools/store_shot.swift")
        let screens = Self.screenNames(in: generator)
        #expect(screens.count == 5, "the generator lists \(screens.sorted())")

        let painted = Self.screenNames(in: renderer)
        #expect(painted == screens, "the renderer has backgrounds for \(painted.sorted())")

        let data = try Data(contentsOf: Self.repositoryRoot.appendingPathComponent("store/headlines.json"))
        let headlines = try JSONSerialization.jsonObject(with: data) as? [String: [String: String]] ?? [:]
        #expect(Set(headlines.keys) == screens, "headlines exist for \(headlines.keys.sorted())")

        let languages = Set(AppLanguage.allCases.map(\.rawValue)).subtracting(["system"])
        for (screen, words) in headlines {
            #expect(Set(words.keys) == languages, "\(screen) is headlined in \(words.keys.sorted())")
            for (language, word) in words {
                #expect(!word.isEmpty && word.count <= 14,
                        "\(screen)/\(language): \"\(word)\" is not one short word")
            }
        }
    }

    private static func tool(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
    }

    /// Every quoted `NN-name` in a source file — the screenshot names, and only
    /// them. Anchored on the name's own shape rather than on pairs of quotes:
    /// a scan that pairs quotes loses its footing at the first `\n` and comes
    /// back with the text *between* the literals.
    private static func screenNames(in source: String) -> Set<String> {
        Set(source.matches(of: /"(0[1-5]-[a-z]+)"/).map { String($0.1) })
    }

    private static func locales() throws -> Set<String> {
        let root = repositoryRoot.appendingPathComponent("store/metadata")
        let found = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { !$0.hasPrefix(".") }
        guard found.count >= 10 else {
            throw ScanIsLookingInTheWrongPlace(what: "listing", found: found.count, least: 10)
        }
        return Set(found)
    }

    private static func read(_ field: String, in locale: String) throws -> String {
        let url = repositoryRoot
            .appendingPathComponent("store/metadata/\(locale)/\(field).txt")
        return try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
