import Testing
import Foundation
@testable import StatusUI

/// Every key in the catalogues is used somewhere.
///
/// Adding a string is easy and tidy — `tools/add_strings.py` puts it in all ten
/// languages at once. Removing one is neither: the call site goes, the ten
/// entries stay, and nothing notices. The existing check compares the languages
/// against each other, and ten copies of a dead key agree with one another
/// perfectly.
///
/// The cost of letting them accumulate is paid by whoever translates next, on
/// strings nothing will ever show.
@Suite struct NoOrphanStrings {

    /// Keys that are looked up but never written as a literal at the call site.
    /// Each is composed at runtime, and each is listed here rather than being
    /// guessed at by the scan.
    private static let composed: Set<String> = [
        "%lldd", "%lldh", "%lldm",   // built by `unit(_:)` from a RemainingTime case
    ]

    @Test func everyKeyIsUsedSomewhere() throws {
        let keys = try Self.englishKeys()
        #expect(keys.count > 40, "the catalogue looks too small: \(keys.count)")

        let sources = try Self.sourceText()
        let orphans = keys
            .subtracting(Self.composed)
            .filter { !sources.contains("\"\($0)\"") }

        #expect(orphans.isEmpty, """
            in all ten catalogues and used nowhere: \(orphans.sorted()) \
            — remove them, or add them to `composed` if they are built at runtime
            """)
    }

    // MARK: - reading

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

    /// Every Swift source that could ask for a string, as one blob. Tests are
    /// left out: a key used only by a test is an orphan in the interface.
    private static func sourceText() throws -> String {
        let roots = ["Packages/Core/Sources", "App", "Widget", "iOS", "iOSWidget"]
        var all = ""
        for name in roots {
            let root = repositoryRoot.appendingPathComponent(name)
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
            else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                all += (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            }
        }
        return all
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
