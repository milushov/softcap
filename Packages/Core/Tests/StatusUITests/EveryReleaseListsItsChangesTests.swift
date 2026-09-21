import Testing
import Foundation

/// Every release body opens with the subjects of the commits that changed the
/// app since the previous release, and a push that changed nothing in the app
/// publishes nothing. Both answers come from `tools/release_notes.py`, which
/// reads git; this suite builds a small repository to ask it in, and reads the
/// workflow to see that the answers are the ones it acts on.
///
/// The repository is built under the temporary directory with the machine's
/// git configuration switched off — no global config, no signing, no hooks —
/// and every commit is given its own second, so "oldest first" is a fact the
/// test can check rather than a coincidence of the clock.
@Suite struct EveryReleaseListsItsChanges {

    // MARK: the gate

    @Test func aCommitThatTouchedTheAppMeansABuild() throws {
        let repo = try Fixture()
        defer { repo.discard() }
        try repo.commit("Start", touching: "App/Main.swift")
        try repo.tag("v0.1.1")
        try repo.commit("Let the badge shrink", touching: "App/Badge.swift")

        let answer = try repo.tool("changed")
        #expect(answer.status == 0, "\(answer.err)")
        #expect(answer.out == "true")
    }

    @Test func aPushThatTouchedNothingInTheAppMeansNoBuild() throws {
        let repo = try Fixture()
        defer { repo.discard() }
        try repo.commit("Start", touching: "App/Main.swift")
        try repo.tag("v0.1.1")
        try repo.commit("Photograph the app", touching: "tools/store_shot.swift")
        try repo.commit("Rewrite the landing", touching: "site/index.html")
        try repo.commit("Write the listing", touching: "store/metadata/en-US/name.txt")
        try repo.commit("Strengthen a guard",
                        touching: "Packages/Core/Tests/StatusUITests/AGuardTests.swift")
        try repo.commit("Log a decision", touching: "docs/DECISIONS.md")

        let answer = try repo.tool("changed")
        #expect(answer.status == 0, "\(answer.err)")
        #expect(answer.out == "false", """
            a push to the site, the store, the tests and the docs reads as a \
            change to the app — the version would move and the app would not
            """)
    }

    @Test func aRepositoryWithNoReleaseYetIsBuilt() throws {
        let repo = try Fixture()
        defer { repo.discard() }
        try repo.commit("Start", touching: "site/index.html")

        let answer = try repo.tool("changed")
        #expect(answer.status == 0, "\(answer.err)")
        #expect(answer.out == "true", "a fresh fork never gets its first release")
    }

    @Test func aShallowCheckoutIsRefusedRatherThanAnsweredWrong() throws {
        let repo = try Fixture()
        defer { repo.discard() }
        try repo.commit("Start", touching: "App/Main.swift")
        try repo.tag("v0.1.1")
        try repo.commit("Let the badge shrink", touching: "App/Badge.swift")
        let shallow = try repo.shallowClone()
        defer { shallow.discard() }

        // In a shallow checkout the tag is out of reach, and "no previous
        // release" would list nothing and build everything without a word.
        let gate = try shallow.tool("changed")
        #expect(gate.status == 2, "a shallow checkout answered \(gate.out)")
        #expect(gate.err.contains("fetch-depth: 0"),
                "the refusal does not say which checkout option it needs")
        let notes = try shallow.tool("notes")
        #expect(notes.status == 2, "the notes were written from a shallow checkout")
    }

    // MARK: the list

    @Test func theCommitsThatChangedTheAppAreListedOldestFirst() throws {
        let repo = try Fixture()
        defer { repo.discard() }
        try repo.commit("Start", touching: "App/Main.swift")
        try repo.tag("v0.1.1")
        try repo.commit("Let the badge shrink [skip ci]", touching: "App/Badge.swift")
        try repo.commit("Rewrite the landing", touching: "site/index.html")
        try repo.commit("Read the widget's folder", touching: "Widget/Reader.swift")
        try repo.commit("Strengthen a guard",
                        touching: "Packages/Core/Tests/StatusUITests/AGuardTests.swift")
        try repo.commit("Sign with a timestamp", touching: "tools/sign_app.sh")
        try repo.merge("Give the chart its dates", touching: "Packages/Core/Sources/Chart.swift")

        let answer = try repo.tool("notes")
        #expect(answer.status == 0, "\(answer.err)")
        let listed = answer.out.split(separator: "\n").filter { $0.hasPrefix("- ") }
        #expect(listed == [
            "- Let the badge shrink",
            "- Read the widget's folder",
            "- Sign with a timestamp",
            "- Give the chart its dates",
        ], """
            the list is not the commits that changed the app, oldest first, \
            with the CI instruction trimmed and the merge commit left out
            """)
        #expect(!answer.out.contains("Merge topic"))
    }

    @Test func aRebuildSaysNothingChanged() throws {
        let repo = try Fixture()
        defer { repo.discard() }
        try repo.commit("Start", touching: "App/Main.swift")
        try repo.tag("v0.1.1")
        try repo.commit("Rewrite the landing", touching: "site/index.html")

        let answer = try repo.tool("notes")
        #expect(answer.status == 0, "\(answer.err)")
        #expect(answer.out.hasPrefix("Nothing in the app changed since 0.1.1"), "\(answer.out)")
        #expect(!answer.out.contains("\n- "), "a rebuild lists something")
    }

    @Test func theReleasedCommitBuiltAgainIsARebuild() throws {
        let repo = try Fixture()
        defer { repo.discard() }
        try repo.commit("Start", touching: "App/Main.swift")
        try repo.tag("v0.1.1")

        let answer = try repo.tool("notes")
        #expect(answer.status == 0, "\(answer.err)")
        #expect(answer.out.hasPrefix("Nothing in the app changed since 0.1.1"), "\(answer.out)")
    }

    @Test func theBodyNamesTheCommitAndLinksEverythingSinceTheLastRelease() throws {
        let repo = try Fixture()
        defer { repo.discard() }
        try repo.commit("Start", touching: "App/Main.swift")
        try repo.tag("v0.1.1")
        try repo.commit("Let the badge shrink", touching: "App/Badge.swift")
        let head = try repo.shortHead()

        let linked = try repo.tool("notes", "--tag", "v0.1.2", "--repository", "owner/name")
        #expect(linked.status == 0, "\(linked.err)")
        let built = linked.out.split(separator: "\n").last.map(String.init) ?? ""
        // The list, a blank line, then this — the shape the workflow appends to.
        #expect(linked.out.contains("\n\nBuilt from `\(head)` on "), "\(linked.out)")
        #expect(built.range(of: #"on \d{4}-\d{2}-\d{2} — "#, options: .regularExpression) != nil,
                "\(built)")
        #expect(built.hasSuffix(
            "[everything since 0.1.1](https://github.com/owner/name/compare/v0.1.1...v0.1.2)."),
            "\(built)")

        // A preview at a terminal has no tag and no repository to link to.
        let plain = try repo.tool("notes")
        #expect(plain.status == 0, "\(plain.err)")
        #expect(!plain.out.contains("compare/"), "\(plain.out)")
        #expect(plain.out.range(of: #"Built from `[0-9a-f]{7}` on \d{4}-\d{2}-\d{2}\.$"#,
                                options: .regularExpression) != nil, "\(plain.out)")
    }

    @Test func theFirstReleaseHasNothingToBeSince() throws {
        let repo = try Fixture()
        defer { repo.discard() }
        try repo.commit("Start", touching: "App/Main.swift")

        let answer = try repo.tool("notes", "--tag", "v0.1.1", "--repository", "owner/name")
        #expect(answer.status == 0, "\(answer.err)")
        #expect(answer.out.hasPrefix("Built from `"), "\(answer.out)")
        #expect(!answer.out.contains("since"), "\(answer.out)")
    }

    // MARK: the workflow

    @Test func theBuildIsGatedOnTheToolsAnswer() throws {
        let workflow = try Self.read(".github/workflows/release.yml", least: 20_000)
        let changes = try Self.job("changes", in: workflow)
        #expect(changes.contains("python3 tools/release_notes.py changed"),
                "the changes job no longer asks the tool")
        #expect(changes.contains("changed=$(python3 tools/release_notes.py changed)"), """
            the answer is read inside an echo, where a tool that fails leaves \
            an empty answer and a green step
            """)

        let release = try Self.job("release", in: workflow)
        #expect(release.contains("needs: [test, changes]"),
                "the release job no longer waits for the answer")
        #expect(release.contains(
            "if: needs.changes.outputs.app == 'true' || github.event_name == 'workflow_dispatch'"
        ), "the release job builds whether or not the app changed, or cannot be asked for by hand")
    }

    @Test func bothJobsThatReadTheHistoryCheckItOut() throws {
        let workflow = try Self.read(".github/workflows/release.yml", least: 20_000)
        for name in ["changes", "release"] {
            let job = try Self.job(name, in: workflow)
            #expect(job.contains("fetch-depth: 0"), """
                the \(name) job checks out one commit, and the tool refuses a \
                shallow checkout — the run would fail at the first question
                """)
        }
    }

    @Test func theNotesLeadWithTheList() throws {
        let workflow = try Self.read(".github/workflows/release.yml", least: 20_000)
        let release = try Self.job("release", in: workflow)
        guard let list = release.range(of: "tools/release_notes.py notes"),
              let install = release.range(of: "**Install**") else {
            Issue.record("the release notes step no longer runs the tool, or no longer says how to install")
            return
        }
        #expect(list.lowerBound < install.lowerBound, """
            the install paragraph comes before the list, and the Updates screen \
            in the app shows the top of the body
            """)
        #expect(release.contains("--tag \"${{ steps.v.outputs.tag }}\""),
                "the notes are written without the tag, so the compare link is missing")
        #expect(release.contains("--repository \"${{ github.repository }}\""),
                "the notes are written without the repository, so the compare link is missing")
    }

    /// The lines of one job: from `  name:` to the next two-space key.
    private static func job(_ name: String, in workflow: String) throws -> String {
        var lines: [Substring] = []
        var inside = false
        for line in workflow.split(separator: "\n", omittingEmptySubsequences: false) {
            if line == "  \(name):" { inside = true; continue }
            if inside, line.range(of: #"^  [a-z]+:$"#, options: .regularExpression) != nil { break }
            if inside { lines.append(line) }
        }
        guard !lines.isEmpty else {
            throw ScanIsLookingInTheWrongPlace(what: "\(name) job", found: 0, least: 1)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: -

    /// A git repository of its own, thrown away afterwards.
    private final class Fixture {
        let directory: URL
        /// One second per commit, so that dates order the log the way the
        /// commits were made.
        private var tick = 0

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("softcap-release-notes-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try git("init", "-q", "-b", "main")
        }

        private init(at directory: URL) { self.directory = directory }

        func discard() { try? FileManager.default.removeItem(at: directory) }

        /// A commit whose only change is `path`. The file's content is the
        /// commit's number, so that touching the same path twice is two changes.
        func commit(_ subject: String, touching path: String) throws {
            let file = directory.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "\(tick + 1)\n".write(to: file, atomically: true, encoding: .utf8)
            try git("add", "-A")
            try git("commit", "-q", "-m", subject)
        }

        func tag(_ name: String) throws { try git("tag", name) }

        /// A commit on a branch, merged back with a merge commit of its own.
        func merge(_ subject: String, touching path: String) throws {
            try git("checkout", "-q", "-b", "topic")
            try commit(subject, touching: path)
            try git("checkout", "-q", "main")
            try git("merge", "-q", "--no-ff", "-m", "Merge topic", "topic")
        }

        /// `--depth 1`, over `file://` — a plain path would be a local clone,
        /// which ignores the depth.
        func shallowClone() throws -> Fixture {
            let clone = FileManager.default.temporaryDirectory
                .appendingPathComponent("softcap-release-notes-shallow-\(UUID().uuidString)")
            try git("clone", "-q", "--depth", "1", "file://" + directory.path, clone.path)
            return Fixture(at: clone)
        }

        func shortHead() throws -> String { try git("rev-parse", "--short=7", "HEAD").out }

        struct Answer { let status: Int32, out: String, err: String }

        /// Runs the tool in the repository. Not `git` — failing is one of the
        /// answers a test asks for.
        func tool(_ arguments: String...) throws -> Answer {
            try run("python3", [EveryReleaseListsItsChanges.toolPath] + arguments)
        }

        @discardableResult
        private func git(_ arguments: String...) throws -> Answer {
            let answer = try run("git", arguments)
            guard answer.status == 0 else { throw GitRefused(arguments: arguments, said: answer.err) }
            return answer
        }

        private func run(_ program: String, _ arguments: [String]) throws -> Answer {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [program] + arguments
            process.currentDirectoryURL = directory

            var environment = ProcessInfo.processInfo.environment
            // Nothing from this machine: not its global config, not its
            // signing key, not its hooks, not its name.
            environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
            environment["GIT_CONFIG_NOSYSTEM"] = "1"
            environment["GIT_AUTHOR_NAME"] = "Softcap tests"
            environment["GIT_AUTHOR_EMAIL"] = "tests@example.com"
            environment["GIT_COMMITTER_NAME"] = "Softcap tests"
            environment["GIT_COMMITTER_EMAIL"] = "tests@example.com"
            tick += 1
            let date = "@\(1_790_000_000 + tick) +0000"
            environment["GIT_AUTHOR_DATE"] = date
            environment["GIT_COMMITTER_DATE"] = date
            process.environment = environment

            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            try process.run()
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return Answer(
                status: process.terminationStatus,
                out: String(decoding: outData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                err: String(decoding: errData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines))
        }

        struct GitRefused: Error, CustomStringConvertible {
            let arguments: [String], said: String
            var description: String { "git \(arguments.joined(separator: " ")) refused: \(said)" }
        }
    }

    private static var toolPath: String {
        repositoryRoot().appendingPathComponent("tools/release_notes.py").path
    }

    private static func read(_ path: String, least: Int) throws -> String {
        let text = try String(
            contentsOf: repositoryRoot().appendingPathComponent(path), encoding: .utf8)
        guard text.count >= least else {
            throw ScanIsLookingInTheWrongPlace(what: path, found: text.count, least: least)
        }
        return text
    }

    private static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // …/StatusUITests
            .deletingLastPathComponent()      // …/Tests
            .deletingLastPathComponent()      // …/Core
            .deletingLastPathComponent()      // …/Packages
            .deletingLastPathComponent()      // repository root
    }
}
