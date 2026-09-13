import Testing
import Foundation

/// Two log lines shipped reading "…s old,             4 accounts".
///
/// Nothing was wrong with the Swift: the gap was baked into the literal by the
/// editing, and a multi-line string keeps whatever is inside it. It survived a
/// build, a test run and a commit, because every check this project has asks
/// whether a string is *present*, and it was.
///
/// So this asks the other question: does it read as a sentence. Both surfaces
/// where the answer matters — what the reader sees, and what the log says when
/// somebody is finally looking at it.
@Suite struct SentencesReadAsSentences {

    /// Three, not two: the catalogues are prose, and no sentence in them has a
    /// reason to hold a run that long. Two would refuse the double space some
    /// writers still put after a full stop.
    private static let tooManySpaces = try! NSRegularExpression(pattern: #"\S {3,}\S"#)

    @Test func noTranslationHasAGapInsideIt() throws {
        let catalogues = try Self.catalogues()
        guard catalogues.count >= 10 else {
            throw ScanIsLookingInTheWrongPlace(
                what: "catalogue", found: catalogues.count, least: 10)
        }
        for (name, text) in catalogues {
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where Self.hasAGap(String(line)) {
                Issue.record("""
                    \(name) line \(number + 1) holds a run of spaces inside the text: \
                    \(line.trimmingCharacters(in: .whitespaces).prefix(70))
                    """)
            }
        }
    }

    @Test func noLoggedSentenceHasAGapInsideIt() throws {
        let files = try Self.swiftFiles()
        guard files.count >= 40 else {
            throw ScanIsLookingInTheWrongPlace(what: "source", found: files.count, least: 40)
        }
        var examined = 0
        for file in files {
            var insideALoggedString = false
            for (number, line) in try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                if line.contains("log.") && line.contains("\"\"\"") {
                    insideALoggedString = true
                    continue
                }
                guard insideALoggedString else { continue }
                if line.contains("\"\"\"") { insideALoggedString = false; continue }
                examined += 1
                if Self.hasAGap(String(line)) {
                    Issue.record("""
                        \(file.lastPathComponent) line \(number + 1) holds a run of spaces \
                        inside a logged sentence: \(line.trimmingCharacters(in: .whitespaces).prefix(70))
                        """)
                }
            }
        }
        // Three multi-line log calls today, four lines of text between them —
        // down from five calls, because removing the Codex file reader and the
        // Claude Code keychain read took one apiece. The floor is what proves
        // the walk found them, not a target: it was set at ten on a guess and
        // refused its own first run, which is the check working — a scan that
        // comes back thin must say so.
        guard examined >= 4 else {
            throw ScanIsLookingInTheWrongPlace(
                what: "logged sentence line", found: examined, least: 4)
        }
    }

    /// The third surface, and the one that caught the author out twice more
    /// after the first two were fixed: the sentence a failing check prints. Nine
    /// of them had a run of spaces in the middle, all from the same editing, all
    /// invisible until something failed and somebody read the message.
    ///
    /// Only the blocks opened on an `#expect` or `Issue.record` line — a
    /// multi-line string in a test can also be an expected value, and columns in
    /// one of those may be lined up on purpose.
    @Test func noExpectationSaysItsPieceWithAGapInIt() throws {
        var examined = 0
        for file in try Self.testFiles() {
            var insideAMessage = false
            for (number, line) in try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                if !insideAMessage {
                    if (line.contains("#expect(") || line.contains("Issue.record("))
                        && line.contains("\"\"\"") { insideAMessage = true }
                    continue
                }
                if line.contains("\"\"\"") { insideAMessage = false; continue }
                examined += 1
                if Self.hasAGap(String(line)) {
                    Issue.record("""
                        \(file.lastPathComponent) line \(number + 1) holds a run of spaces \
                        inside what a failing check will print
                        """)
                }
            }
        }
        guard examined >= 40 else {
            throw ScanIsLookingInTheWrongPlace(
                what: "expectation message line", found: examined, least: 40)
        }
    }

    // MARK: -

    /// Leading indentation is the file's, not the sentence's — a multi-line
    /// string strips it. Only what follows the first non-space is text.
    private static func hasAGap(_ line: String) -> Bool {
        // Made a String *before* the range is taken from it: indices belong to
        // the string they came from, and a Substring's do not survive the copy.
        let text = String(line.drop(while: \.isWhitespace))
        guard !text.isEmpty else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return tooManySpaces.firstMatch(in: text, range: range) != nil
    }

    private static func catalogues() throws -> [(String, String)] {
        let resources = repositoryRoot
            .appendingPathComponent("Packages/Core/Sources/StatusUI/Resources")
        return try FileManager.default
            .contentsOfDirectory(at: resources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "lproj" }
            .compactMap { folder in
                let file = folder.appendingPathComponent("Localizable.strings")
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
                return (folder.lastPathComponent, text)
            }
    }

    /// The tests themselves, which the other two walks skip on purpose.
    private static func testFiles() throws -> [URL] {
        let tests = repositoryRoot.appendingPathComponent("Packages/Core/Tests")
        guard let walker = FileManager.default.enumerator(
            at: tests, includingPropertiesForKeys: nil) else { return [] }
        var found: [URL] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            found.append(url)
        }
        return found
    }

    private static func swiftFiles() throws -> [URL] {
        let skipped = [".build", ".git", ".claude", "build", "build-ios", "DerivedData", "Tests"]
        guard let walker = FileManager.default.enumerator(
            at: repositoryRoot, includingPropertiesForKeys: nil) else { return [] }
        var found: [URL] = []
        for case let url as URL in walker {
            if skipped.contains(url.lastPathComponent) { walker.skipDescendants(); continue }
            if url.pathExtension == "swift" { found.append(url) }
        }
        return found
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
