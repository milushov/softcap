import Testing
import Foundation

/// The guard on an architectural rule: models hold no strings meant for a person.
///
/// Without a check the rule erodes: sooner or later somebody adds a convenient
/// label straight into a model, and the language is welded back into the core.
/// String literals are scanned, not comments — a comment is written for whoever
/// reads the code, and carries no text to a user.
///
/// **What this can and cannot see.** The script checks catch a *translated*
/// string reaching a model, which is the shape the rule breaks in when somebody
/// is working in another language. They cannot catch an English one, and no
/// check can: `ProviderFailure.diagnostic` is English by design — it goes to the
/// log while the interface shows a translated sentence — and there are thirty
/// such literals of three words or more. "Profile not parsed" and "Almost
/// exhausted" are the same shape to a scanner and opposite in kind.
///
/// So the third check takes the mechanism instead of the text. A label has to be
/// translated, translating goes through `Localization`, and no module here
/// touches it. That is the path the rule actually erodes along, and it is exact.
@Suite struct CoreHasNoHumanStrings {

    /// Every module in `Sources` except the ones named here.
    ///
    /// It was a list of the six modules that existed when it was written, and a
    /// seventh — `Updates` — joined the package and escaped the rule silently.
    /// A list of what is covered has to be edited to stay true; a list of what
    /// is exempt has to be edited to become false, and CLAUDE.md names this test
    /// as where the rule lives.
    ///
    /// `StatusUI` is exempt deliberately: it holds the translations and the
    /// language names in their own scripts ("Русский", "العربية").
    private static let exempt: Set<String> = ["StatusUI"]

    private static var moduleNames: [String] {
        get throws {
            let found = try FileManager.default
                .contentsOfDirectory(at: sourcesRoot, includingPropertiesForKeys: nil)
                .filter { $0.hasDirectoryPath }
                .map(\.lastPathComponent)
                .filter { !exempt.contains($0) }
                .sorted()
            guard found.count >= 6 else {
                throw ScanIsLookingInTheWrongPlace(
                    what: "model module", found: found.count, least: 6)
            }
            return found
        }
    }

    @Test func modelsCarryNoCyrillicLiterals() throws {
        let offenders = try Self.scan(for: "\\p{Cyrillic}")
        #expect(offenders.isEmpty, "strings meant for a person, inside models: \(offenders.joined(separator: "; "))")
    }

    @Test func modelsCarryNoArabicOrCJKLiterals() throws {
        let offenders = try Self.scan(for: "[\\p{Arabic}\\p{Han}\\p{Devanagari}]")
        #expect(offenders.isEmpty, "strings meant for a person, inside models: \(offenders.joined(separator: "; "))")
    }

    /// Not the words — the machinery. A string shown to somebody has to be
    /// translated, and translating goes through `Localization`; a model that
    /// reaches for it is a model that has started holding a label, whatever the
    /// literal beside it looks like.
    @Test func noModelReachesForTheTranslations() throws {
        var offenders: [String] = []
        var examined = 0
        for module in try Self.moduleNames {
            let directory = Self.sourcesRoot.appendingPathComponent(module)
            guard let walker = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                examined += 1
                let text = Self.stripComments(try String(contentsOf: url, encoding: .utf8))
                for machinery in ["Localization", "NSLocalizedString", "String(localized:"]
                where text.contains(machinery) {
                    offenders.append("\(module)/\(url.lastPathComponent): \(machinery)")
                }
            }
        }
        guard examined >= 15 else {
            throw ScanIsLookingInTheWrongPlace(what: "model source", found: examined, least: 15)
        }
        #expect(offenders.isEmpty, """
            a model reaches for the translations: \(offenders.joined(separator: "; ")) — \
            labels are assembled by the interface, and a model that can translate \
            is a model that holds one
            """)
    }

    // MARK: - scanning

    private static func scan(for pattern: String) throws -> [String] {
        var offenders: [String] = []
        for module in try moduleNames {
            let directory = sourcesRoot.appendingPathComponent(module)
            guard let walker = FileManager.default.enumerator(at: directory,
                                                              includingPropertiesForKeys: nil)
            else { continue }

            for case let url as URL in walker where url.pathExtension == "swift" {
                let text = try String(contentsOf: url, encoding: .utf8)
                for literal in stringLiterals(in: stripComments(text))
                where literal.range(of: pattern, options: .regularExpression) != nil {
                    offenders.append("\(module)/\(url.lastPathComponent): \"\(literal)\"")
                }
            }
        }
        return offenders
    }

    /// The path to the sources, taken from the test file: `#filePath` does not
    /// depend on where the tests were launched from, unlike the process's
    /// working directory.
    private static var sourcesRoot: URL {
        URL(fileURLWithPath: #filePath)          // …/Tests/StatusUITests/<file>.swift
            .deletingLastPathComponent()          // …/Tests/StatusUITests
            .deletingLastPathComponent()          // …/Tests
            .deletingLastPathComponent()          // …/Core
            .appendingPathComponent("Sources")
    }

    fileprivate static func stripComments(_ text: String) -> String {
        var result = ""
        var inBlockComment = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var piece = String(line)
            if inBlockComment {
                guard let end = piece.range(of: "*/") else { continue }
                piece = String(piece[end.upperBound...])
                inBlockComment = false
            }
            if let start = piece.range(of: "/*") {
                piece = String(piece[..<start.lowerBound])
                inBlockComment = true
            }
            if let line = piece.range(of: "//") {
                piece = String(piece[..<line.lowerBound])
            }
            result += piece + "\n"
        }
        return result
    }

    private static func stringLiterals(in text: String) -> [String] {
        let pattern = #""([^"\\\n]|\\.)*""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            return String(text[r].dropFirst().dropLast())
        }
    }
}
