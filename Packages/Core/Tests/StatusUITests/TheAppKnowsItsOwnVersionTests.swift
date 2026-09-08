import Testing
import Foundation

/// The updater compares the running version against the newest release, so an
/// app that misreports its own version is permanently out of date and says so
/// forever.
///
/// It did. `project.yml` set `CFBundleShortVersionString` as a literal on the
/// app target while the widget beside it used `$(MARKETING_VERSION)`, and the
/// release workflow passes the version on the command line — so the widget
/// followed it and the app did not. Nothing depended on the number before,
/// which is the only reason it cost nothing.
///
/// Checked in the project description rather than in a built app: the built app
/// is not there on a machine that has only run `make test`.
@Suite struct TheAppKnowsItsOwnVersion {

    @Test func everyBundleTakesItsVersionFromTheBuildSetting() throws {
        let text = try String(contentsOf: Self.projectFile, encoding: .utf8)
        let literals = Self.matches(#"CFBundleShortVersionString:\s*"([^"]*)""#, in: text)

        guard literals.count >= 4 else {
            throw ScanIsLookingInTheWrongPlace(
                what: "version declaration", found: literals.count, least: 4)
        }

        let hardcoded = literals.filter { $0 != "$(MARKETING_VERSION)" }
        #expect(hardcoded.isEmpty, """
            a bundle names its version outright: \(hardcoded.joined(separator: ", ")) \
            — the release workflow passes MARKETING_VERSION on the command line, and a \
            literal ignores it
            """)
    }

    /// The About screen reads this one too, and showed a bare "1" because
    /// nothing set it.
    ///
    /// A build number is not a marketing version. Making it one put
    /// "0.1.47 (0.1.47)" on the About screen and, on the two iOS targets whose
    /// marketing version is a literal, moved a shipped build number backwards —
    /// which the App Store refuses outright. It has its own setting again.
    ///
    /// The first version of this check was `contains("CFBundleVersion:")`, which
    /// passed for any value at all, including the wrong one it was written just
    /// after introducing.
    @Test func theBuildNumberIsItsOwnSetting() throws {
        let text = try String(contentsOf: Self.projectFile, encoding: .utf8)
        let declared = Self.matches(#"CFBundleVersion:\s*"([^"]*)""#, in: text)

        guard declared.count >= 4 else {
            throw ScanIsLookingInTheWrongPlace(
                what: "build number declaration", found: declared.count, least: 4)
        }

        let wrong = declared.filter { $0 != "$(CURRENT_PROJECT_VERSION)" }
        #expect(wrong.isEmpty, """
            a bundle takes its build number from somewhere else: \(wrong.joined(separator: ", ")) \
            — the marketing version is not a build number, and using it printed the same \
            number twice on the About screen
            """)

        let defined = Self.matches(#"CURRENT_PROJECT_VERSION:\s*"([^"]*)""#, in: text)
        #expect(defined.count >= 4, """
            \(defined.count) targets define CURRENT_PROJECT_VERSION and \(declared.count) \
            read it — one of them resolves to nothing
            """)
    }

    /// The two iOS targets are not part of a release and receive no override, so
    /// a version taken from the Mac app is simply the Mac app's number sitting
    /// on a different product. Theirs was 1.0 and briefly became 0.1.
    @Test func thePhoneKeepsItsOwnVersion() throws {
        let text = try String(contentsOf: Self.projectFile, encoding: .utf8)
        let versions = Self.matches(#"MARKETING_VERSION:\s*"([^"]*)""#, in: text)
        #expect(versions.filter { $0 == "1.0" }.count == 2, """
            the iOS app and its widget no longer carry 1.0: \(versions) — the release \
            workflow builds only the macOS scheme, so nothing overrides theirs
            """)
    }

    private static var projectFile: URL {
        repositoryRoot.appendingPathComponent("project.yml")
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let whole = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: whole).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)      // …/Packages/Core/Tests/StatusUITests/<file>.swift
            .deletingLastPathComponent()      // …/Tests/StatusUITests
            .deletingLastPathComponent()      // …/Tests
            .deletingLastPathComponent()      // …/Core
            .deletingLastPathComponent()      // …/Packages
            .deletingLastPathComponent()      // repository root
    }
}
