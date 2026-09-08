import Testing
import Foundation

/// `tools/mutate` breaks a file on purpose and requires a check to notice. Its
/// three exit codes are the whole interface, and the README states them — two
/// copies of one fact, which is the shape this suite exists to prevent.
///
/// It is also the tool the rest of these guards are proven with, so a change to
/// it that the README does not follow would mislead about the one thing nobody
/// double-checks: what a green result means.
@Suite struct TheMutationToolSaysWhatItDoes {

    @Test func theToolIsThereAndRunnable() throws {
        let path = Self.repositoryRoot.appendingPathComponent("tools/mutate")
        #expect(FileManager.default.isExecutableFile(atPath: path.path),
                "tools/mutate is missing or not executable")
    }

    @Test func theExitCodesAreTheOnesTheReadmeStates() throws {
        let tool = try Self.read("tools/mutate", least: 2_000)
        // Squashed: both phrases wrap across a line in the README, and a check
        // that reads the file as-is refuses a sentence that was only rewrapped.
        // `ReadingProse` records this happening three times before.
        let readme = try Self.read("README.md", least: 5_000)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")

        // Each code, as the tool returns it and as the README explains it.
        #expect(tool.contains("sys.exit(main(sys.argv[1:]))"),
                "the tool no longer returns its own exit code")
        for (code, meaning) in [("0", "the check failed"),
                                ("1", "the check passed with the file broken"),
                                ("2", "the mutation could not be made")] {
            #expect(tool.contains("  \(code)  "), "the tool no longer documents exit \(code)")
            #expect(readme.says(meaning), """
                the README no longer says what exit \(code) means — it reads \
                "\(meaning)"
                """)
        }
    }

    /// The three rules it exists to enforce, each written down in the decision log
    /// after being learned the hard way. A tool that dropped one would still run.
    @Test func theToolStillEnforcesWhatItWasWrittenFor() throws {
        let tool = try Self.read("tools/mutate", least: 2_000)

        #expect(tool.contains("nothing in {path} matches"), """
            a mutation that changes nothing is no longer an error, so a wrong \
            replacement reads as a passing guard
            """)
        #expect(tool.contains("has uncommitted changes"), """
            the tool no longer refuses a dirty file, and a restore is then \
            indistinguishable from losing the work
            """)
        #expect(tool.contains("shutil.copyfile"), "the restore no longer comes from a copy")
        // The operation, not the words. The docstring names `git checkout --` as
        // the thing that went wrong, and forbidding the phrase outright failed on
        // the explanation of why it is not used.
        #expect(!tool.contains("\"git\", \"checkout\""), """
            the tool restores through git, which is what threw away uncommitted \
            work twice
            """)
    }

    // MARK: -

    private static func read(_ path: String, least: Int) throws -> String {
        let text = try String(
            contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
        guard text.count >= least else {
            throw ScanIsLookingInTheWrongPlace(what: path, found: text.count, least: least)
        }
        return text
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
