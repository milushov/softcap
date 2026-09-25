import Testing
import Foundation

/// A service is named in one place, and every screen reads it from there.
///
/// Three screens offer a person a choice of service: the Accounts menu, the
/// Services list, and the menu bar's **Add account…** submenu. All three wrote
/// the name inline, and while there were two services all three could do it
/// with the same question — `provider == .claude ? "Claude Code" : "OpenAI
/// Codex"`. A ternary is a complete answer for two and a wrong answer for
/// three, and it does not fail: it names the third service after the second.
///
/// That is what happened. Two of the three were changed to read
/// `ProviderID.productName` when the third service arrived and the menu bar's
/// was missed, so Copilot appeared in the menu bar as `OpenAI Codex` — an item
/// that looks right, sits beside an identical one, and signs into the wrong
/// service when pressed. Nothing else would have caught it: it is a title, not
/// a behaviour, and the tests that read this app's screens read its strings
/// catalogue, which a brand name is deliberately not in.
///
/// So the names live in `ProviderNaming.swift` and nowhere else. A fourth
/// screen written the old way fails here rather than shipping.
@Suite struct OneNamePerService {

    /// The product names, as a person choosing between services reads them.
    private static let productNames = [
        "Claude Code", "OpenAI Codex", "GitHub Copilot", "GLM Coding Plan", "Kimi Code",
    ]

    @Test func noScreenWritesAProductNameOfItsOwn() throws {
        let files = try Self.appSources()

        // Vacuous otherwise: a walk that finds nothing approves everything, and
        // this one starts at a path built out of five `..` components.
        guard files.count >= 15 else {
            throw ScanIsLookingInTheWrongPlace(what: "app source", found: files.count, least: 15)
        }

        var offenders: [String: [String]] = [:]        // file -> names it writes
        for file in files where file.lastPathComponent != "ProviderNaming.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            let written = Self.productNames.filter { text.contains("\"\($0)\"") }
            if !written.isEmpty { offenders[file.lastPathComponent] = written }
        }

        #expect(offenders.isEmpty, """
            \(offenders.map { "\($0.key): \($0.value.joined(separator: ", "))" }
                .sorted().joined(separator: "; ")) — \
            a service is named in ProviderNaming.swift and read from there. \
            Written inline it is usually written as a question about two \
            services, which answers a third with the second one's name.
            """)
    }

    /// And the one place that does write them answers every service distinctly.
    /// Two services sharing a name is the same defect arriving by another road.
    @Test func everyServiceHasANameOfItsOwn() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent("App/ProviderNaming.swift"),
            encoding: .utf8)

        for name in Self.productNames {
            #expect(source.contains("\"\(name)\""), """
                ProviderNaming.swift no longer names \(name). If the service was \
                renamed, rename it here and in this test; if it was dropped, the \
                list above is what to change.
                """)
        }

        // Every case answered, and no two alike. `ProviderID` is `CaseIterable`
        // and its `productName` is a `switch` with no `default`, so the compiler
        // already insists every case is answered — this holds the other half,
        // that the answers differ.
        let quoted = source.split(separator: "\n")
            .filter { $0.contains("case .") && $0.contains("\"") }
            .compactMap { line -> String? in
                guard let open = line.firstIndex(of: "\""),
                      let close = line.lastIndex(of: "\""), open < close else { return nil }
                return String(line[line.index(after: open)..<close])
            }
        #expect(quoted.count == Set(quoted).count, """
            two services share a product name in ProviderNaming.swift: \
            \(quoted.sorted().joined(separator: ", ")). A menu offering the same \
            words twice signs into whichever of them was listed first.
            """)
    }

    private struct ScanIsLookingInTheWrongPlace: Error {
        let what: String
        let found: Int
        let least: Int
    }

    /// The app's own sources. Not the package: `Packages/Core` may not name a
    /// service at all beyond `ProviderID.title`, which the architecture rule in
    /// `CLAUDE.md` already covers and `CoreHasNoHumanStrings` already holds.
    private static func appSources() throws -> [URL] {
        let roots = ["App", "iOS", "iOSWidget", "Widget"]
        var found: [URL] = []
        for root in roots {
            let directory = repositoryRoot.appendingPathComponent(root)
            guard let walker = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: nil
            ) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                found.append(url)
            }
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
