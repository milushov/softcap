import Testing
import Foundation

/// `Claude` and `Codex` are names. `claude` is a command.
///
/// One sentence said "otherwise claude would be signed out", meaning Claude
/// Code, in every one of the ten catalogues — it is part of the key, so the
/// mistake was copied ten times by the tooling that keeps them in step. It read
/// as a typo beside "Claude Code" three words earlier.
///
/// The exception is real and has to be allowed: "sign in via claude /login"
/// names the executable, which is lower case. So the rule is not "never lower
/// case" but "lower case only where a command follows".
@Suite struct BrandNamesAreCapitalised {

    private static let brands = ["claude", "codex", "softcap"]

    @Test func noCatalogueWritesANameInLowerCase() throws {
        var offenders: [String] = []
        for url in try Self.catalogues() {
            let language = url.deletingLastPathComponent().lastPathComponent
            let text = try String(contentsOf: url, encoding: .utf8)
            for (number, line) in text.components(separatedBy: "\n").enumerated() {
                for brand in Self.brands {
                    for range in Self.wordRanges(of: brand, in: line)
                    where !Self.isACommand(at: range, in: line) {
                        offenders.append("\(language):\(number + 1) — \(line[range])")
                    }
                }
            }
        }
        #expect(offenders.isEmpty, """
            a name is written in lower case at \(Array(Set(offenders)).sorted()) — \
            capitalise it, unless it is the command, which is followed by its argument
            """)
    }

    /// A command is the executable's name with a slash-argument after it, as in
    /// `claude /login`.
    private static func isACommand(at range: Range<String.Index>, in line: String) -> Bool {
        let rest = line[range.upperBound...]
        return rest.hasPrefix(" /")
    }

    /// Occurrences of `word` in lower case, bounded by non-letters on both sides
    /// — so `claude` matches and `claudette` does not.
    private static func wordRanges(of word: String, in line: String) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        var search = line.startIndex..<line.endIndex
        while let range = line.range(of: word, options: .literal, range: search) {
            let beforeOK = range.lowerBound == line.startIndex
                || !line[line.index(before: range.lowerBound)].isLetter
            let afterOK = range.upperBound == line.endIndex
                || !line[range.upperBound].isLetter
            if beforeOK && afterOK { found.append(range) }
            search = range.upperBound..<line.endIndex
        }
        return found
    }

    private static func catalogues() throws -> [URL] {
        let root = repositoryRoot
            .appendingPathComponent("Packages/Core/Sources/StatusUI/Resources")
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { return [] }
        var found: [URL] = []
        for case let url as URL in walker where url.lastPathComponent == "Localizable.strings" {
            found.append(url)
        }
        return found
    }

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
}
