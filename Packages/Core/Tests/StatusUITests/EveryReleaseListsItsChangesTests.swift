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
