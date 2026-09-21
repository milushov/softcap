# Release Notes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every GitHub release opens with the subjects of the commits that changed the app since the previous release, and a push that changed nothing in the app publishes nothing.

**Architecture:** One Python tool, `tools/release_notes.py`, reads git and answers two questions from one list of paths — *did anything in the app change since the previous release tag* (`changed`) and *what did* (`notes`). The release workflow asks the first in a small job that gates the build, and the second in the build itself to write the top of the release body. A Swift test suite builds a throw-away git repository and runs the tool in it, and reads the workflow to see that it acts on the answers.

**Tech Stack:** Python 3.9-compatible standard library only; GitHub Actions YAML; Swift Testing (`@Suite`/`@Test`) in `Packages/Core`, running the tool through `Foundation.Process` the way `SiteCataloguesAgree` runs `site/build.py`.

**Spec:** `docs/superpowers/specs/2026-09-22-release-notes-design.md`

## Global Constraints

- Documentation, comments and commit messages in English; commit messages carry no agent trailer and no session link.
- Nothing private in any file: no home directory, machine name, real mail address (reserved example domains only), token-shaped value. `NoPersonalDataInTheRepository` runs in the pre-commit hook.
- The tool uses no third-party module and no syntax newer than Python 3.9.
- The list of what counts as the app lives in the tool only — not duplicated into the workflow's `paths` filters. `paths-ignore` stays as it is.
- Every non-obvious decision goes into `docs/DECISIONS.md` (what, why, cost); entries are never rewritten.
- The full suite (`cd Packages/Core && swift test`) is green before every commit; the hook runs it.

---

## File structure

| File | Responsibility |
|---|---|
| `tools/release_notes.py` (new) | Reads git. `changed` → `true`/`false`; `notes` → the top of the release body. Owns `THE_APP`, the one list of paths. Refuses a shallow checkout. |
| `Packages/Core/Tests/StatusUITests/EveryReleaseListsItsChangesTests.swift` (new) | Builds a fixture repository, runs the tool, checks its answers; reads `release.yml` for the wiring. |
| `.github/workflows/release.yml` (modify) | New `changes` job; `release` gated on its output; `fetch-depth: 0` on both history-reading checkouts; the notes step writes the tool's output first. |
| `docs/DECISIONS.md` (append) | The decision, why, and what it costs. |
| `README.md:101-102` (modify) | One sentence describing what the workflow builds. |

---

### Task 1: The fixture and the gate (`changed`)

**Files:**
- Create: `Packages/Core/Tests/StatusUITests/EveryReleaseListsItsChangesTests.swift`
- Create: `tools/release_notes.py`

**Interfaces:**
- Produces: `tools/release_notes.py changed` — prints `true` or `false` and a newline on stdout, exit 0; exit 2 with a message on stderr containing `fetch-depth: 0` in a shallow checkout.
- Produces (for Task 2): `THE_APP`, `NOT_THE_APP`, `previous_release()`, `changes_since(tag)`, `git(*arguments)` inside the tool.
- Produces (for Tasks 2–3): the test suite's `Fixture` class and `read(_:least:)` helper.

- [ ] **Step 1: Write the failing tests and the fixture**

```swift
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
        #expect(answer.status == 0, answer.err)
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
        #expect(answer.status == 0, answer.err)
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
        #expect(answer.status == 0, answer.err)
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
```

- [ ] **Step 2: Run the suite to see it fail**

Run: `cd Packages/Core && swift test --filter EveryReleaseListsItsChanges 2>&1 | tail -20`
Expected: the four tests fail — the tool does not exist, so `python3` exits 2 with "can't open file" on stderr, `out` is empty, and the shallow test's `err` does not mention `fetch-depth`.

- [ ] **Step 3: Write the tool with `changed` and the refusal**

`tools/release_notes.py` (executable, `chmod +x`):

```python
#!/usr/bin/env python3
"""What changed in the app since the previous release, read from git.

    python3 tools/release_notes.py changed
        `true` when a commit since the previous release touched something the
        disk image is made of, `false` otherwise. The release workflow builds
        nothing when this says false — unless it was started by hand.

    python3 tools/release_notes.py notes [--tag v0.1.37] [--repository owner/name]
        The top of the release body: one line per such commit, oldest first,
        then the line naming the commit and the day — with a link to everything
        since the previous release when the tag and the repository are given.

The previous release is the nearest tag shaped like a version that HEAD
descends from. A shallow checkout — what `actions/checkout` makes unless told
otherwise — holds no tag, and in one this would answer "no previous release":
nothing listed, everything built, and no step failing to say so. So a shallow
checkout is refused, with the checkout option it needs in the message.

No third-party modules, and nothing newer than Python 3.9: the runner's own
python3 is what runs this, in the job that decides whether anything else runs.
"""

import argparse
import datetime
import re
import subprocess
import sys

# What the disk image is made of: the sources, the assets, the project that
# builds them, and the pipeline that signs and packages the result — a change
# to signing is a change the person downloading meets. A commit that touched
# none of these did not change the build, however its subject reads: the one
# that let the staleness badge shrink touched the landing page's mock and
# nothing else, and the release it triggered was the same app again.
#
# `:(top)` makes each path relative to the repository's root rather than to
# wherever the tool was run from.
THE_APP = [
    "App",
    "Packages",
    "Widget",
    "Resources",
    "project.yml",
    "Signing.xcconfig",
    ".github/workflows/release.yml",
    "tools/sign_app.sh",
    "tools/make_dmg.sh",
]

# Under Packages, and not in the build.
NOT_THE_APP = [
    "Packages/Core/Tests",
]

# GitHub's five spellings of "run no workflow for this commit" — an instruction
# to CI, not part of the change, and not for the reader.
SKIP_CI = re.compile(
    r"\s*\[(?:skip ci|ci skip|no ci|skip actions|actions skip)\]\s*$", re.IGNORECASE
)

RELEASE_TAG = "v[0-9]*"


def git(*arguments):
    """What git printed, stripped. Raises when git refuses."""
    return subprocess.run(
        ["git", *arguments], check=True, capture_output=True, text=True
    ).stdout.strip()


def refuse_a_shallow_checkout():
    if git("rev-parse", "--is-shallow-repository") == "true":
        print(
            "release-notes: this checkout is shallow, so the previous release's tag "
            "is out of reach and every commit would read as new. Check out the "
            "history: actions/checkout with `fetch-depth: 0`.",
            file=sys.stderr,
        )
        sys.exit(2)


def previous_release():
    """The nearest version tag HEAD descends from, or None before the first."""
    try:
        return git("describe", "--tags", "--abbrev=0", "--match", RELEASE_TAG, "HEAD")
    except subprocess.CalledProcessError:
        return None


def version_of(tag):
    """`v0.1.36` is the tag; `0.1.36` is what the release is called."""
    return tag[1:]


def changes_since(tag):
    """The subjects of the commits since `tag` that touched the app, oldest first."""
    log = git(
        "log", "--no-merges", "--reverse", "--format=%s", tag + "..HEAD", "--",
        *(":(top)" + path for path in THE_APP),
        *(":(top,exclude)" + path for path in NOT_THE_APP),
    )
    return [SKIP_CI.sub("", line) for line in log.splitlines() if line.strip()]


def changed():
    previous = previous_release()
    print("true" if previous is None or changes_since(previous) else "false")


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("changed", help="true or false: did anything in the app change")
    notes_parser = commands.add_parser("notes", help="the top of the release body")
    notes_parser.add_argument("--tag", help="the tag this release will carry, e.g. v0.1.37")
    notes_parser.add_argument("--repository", help="owner/name on GitHub, for the compare link")
    args = parser.parse_args(argv)

    refuse_a_shallow_checkout()
    if args.command == "changed":
        changed()
    else:
        notes(args.tag, args.repository)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

`notes` is Task 2; until then define it as `def notes(tag, repository): raise SystemExit(2)` is **not** acceptable — leave `notes` out of `main` for now? No: the shallow test calls `notes` and expects exit 2 from the refusal, which runs before dispatch. Write Task 2's `notes` function in Task 2; in Task 1 the `else` branch may not be reached by any Task 1 test except the shallow one, which exits before it. To keep the file importable, define in Task 1:

```python
def notes(tag, repository):
    """Task 2."""
    raise NotImplementedError
```

and replace it in Task 2.

- [ ] **Step 4: Run the suite to see it pass**

Run: `cd Packages/Core && swift test --filter EveryReleaseListsItsChanges 2>&1 | tail -20`
Expected: 4 tests pass. If `aPushThatTouchedNothingInTheAppMeansNoBuild` fails with `true`, check that `:(top,exclude)` is accepted by the runner's git (2.39+ is); if the shallow test's `status` is 128, the clone URL lacks `file://`.

Also run the tool by hand at the repository root, from a subdirectory, to see `:(top)` at work:

Run: `python3 tools/release_notes.py changed && (cd Packages && python3 ../tools/release_notes.py changed)`
Expected: two identical answers.

- [ ] **Step 5: Commit**

```bash
git add tools/release_notes.py Packages/Core/Tests/StatusUITests/EveryReleaseListsItsChangesTests.swift
git commit -m "Ask git whether anything in the app changed since the last release"
```

---

### Task 2: The list (`notes`)

**Files:**
- Modify: `tools/release_notes.py` (replace the `notes` placeholder)
- Modify: `Packages/Core/Tests/StatusUITests/EveryReleaseListsItsChangesTests.swift` (add tests under `// MARK: the list`)

**Interfaces:**
- Consumes: `Fixture`, `previous_release()`, `changes_since(tag)`, `version_of(tag)`, `git()`.
- Produces: `tools/release_notes.py notes [--tag T] [--repository R]` printing, on stdout: either `- <subject>` lines or `Nothing in the app changed since <version> — the same sources, built again.`, a blank line, then ``Built from `<short sha>` on <YYYY-MM-DD>`` followed by ` — [everything since <version>](https://github.com/<R>/compare/<previous tag>...<T>)` when both `--tag` and `--repository` are given, and a full stop.

- [ ] **Step 1: Write the failing tests**

Add after the gate tests:

```swift
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
        #expect(answer.status == 0, answer.err)
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
        #expect(answer.status == 0, answer.err)
        #expect(answer.out.hasPrefix("Nothing in the app changed since 0.1.1"), answer.out)
        #expect(!answer.out.contains("\n- "), "a rebuild lists something")
    }

    @Test func theReleasedCommitBuiltAgainIsARebuild() throws {
        let repo = try Fixture()
        defer { repo.discard() }
        try repo.commit("Start", touching: "App/Main.swift")
        try repo.tag("v0.1.1")

        let answer = try repo.tool("notes")
        #expect(answer.status == 0, answer.err)
        #expect(answer.out.hasPrefix("Nothing in the app changed since 0.1.1"), answer.out)
    }

    @Test func theBodyNamesTheCommitAndLinksEverythingSinceTheLastRelease() throws {
        let repo = try Fixture()
        defer { repo.discard() }
        try repo.commit("Start", touching: "App/Main.swift")
        try repo.tag("v0.1.1")
        try repo.commit("Let the badge shrink", touching: "App/Badge.swift")
        let head = try repo.shortHead()

        let linked = try repo.tool("notes", "--tag", "v0.1.2", "--repository", "owner/name")
        #expect(linked.status == 0, linked.err)
        let built = linked.out.split(separator: "\n").last.map(String.init) ?? ""
        // The list, a blank line, then this — the shape the workflow appends to.
        #expect(linked.out.contains("\n\nBuilt from `\(head)` on "), linked.out)
        #expect(built.range(of: #"on \d{4}-\d{2}-\d{2} — "#, options: .regularExpression) != nil, built)
        #expect(built.hasSuffix(
            "[everything since 0.1.1](https://github.com/owner/name/compare/v0.1.1...v0.1.2)."),
            built)

        // A preview at a terminal has no tag and no repository to link to.
        let plain = try repo.tool("notes")
        #expect(plain.status == 0, plain.err)
        #expect(!plain.out.contains("compare/"), plain.out)
        #expect(plain.out.range(of: #"Built from `[0-9a-f]{7}` on \d{4}-\d{2}-\d{2}\.$"#,
                                options: .regularExpression) != nil, plain.out)
    }

    @Test func theFirstReleaseHasNothingToBeSince() throws {
        let repo = try Fixture()
        defer { repo.discard() }
        try repo.commit("Start", touching: "App/Main.swift")

        let answer = try repo.tool("notes", "--tag", "v0.1.1", "--repository", "owner/name")
        #expect(answer.status == 0, answer.err)
        #expect(answer.out.hasPrefix("Built from `"), answer.out)
        #expect(!answer.out.contains("since"), answer.out)
    }
```

- [ ] **Step 2: Run the suite to see the new tests fail**

Run: `cd Packages/Core && swift test --filter EveryReleaseListsItsChanges 2>&1 | tail -30`
Expected: the five new tests fail (`NotImplementedError`, exit 1, empty `out`); the four from Task 1 still pass.

- [ ] **Step 3: Replace the `notes` placeholder**

```python
def notes(tag, repository):
    """The top of the release body, written for two readers at once.

    GitHub renders it under the version; the app's Updates screen shows the
    same text in a box a few lines tall, interpreting inline Markdown only —
    so the list is first, and there is no heading over it to print literally.
    """
    previous = previous_release()
    lines = []
    if previous is not None:
        changes = changes_since(previous)
        if changes:
            lines.extend("- " + subject for subject in changes)
        else:
            lines.append(
                "Nothing in the app changed since %s — the same sources, built again."
                % version_of(previous)
            )
        lines.append("")

    # UTC, as the README's download line is: a release is dated when it was
    # published, not where the author was standing (DECISIONS, 2026-09-14).
    today = datetime.datetime.now(datetime.timezone.utc).date().isoformat()
    built = "Built from `%s` on %s" % (git("rev-parse", "--short=7", "HEAD"), today)
    if previous is not None and tag and repository:
        built += " — [everything since %s](https://github.com/%s/compare/%s...%s)" % (
            version_of(previous), repository, previous, tag
        )
    lines.append(built + ".")
    print("\n".join(lines))
```

- [ ] **Step 4: Run the suite to see it pass**

Run: `cd Packages/Core && swift test --filter EveryReleaseListsItsChanges 2>&1 | tail -20`
Expected: 9 tests pass.

Then look at the real thing once:

Run: `python3 tools/release_notes.py notes --tag v0.1.99 --repository milushov/softcap`
Expected: the subjects of the commits since `v0.1.36` that touched the app (this work's own commits, since they touch `Packages/Core/Tests`? — no: tests are excluded; the tool and the spec are not the app, so expect `Nothing in the app changed since 0.1.36 …` until Task 3 touches `release.yml`), then the `Built from` line with a compare link.

- [ ] **Step 5: Commit**

```bash
git add tools/release_notes.py Packages/Core/Tests/StatusUITests/EveryReleaseListsItsChangesTests.swift
git commit -m "Write the top of the release body from the commits that changed the app"
```

---

### Task 3: The workflow acts on the answers

**Files:**
- Modify: `.github/workflows/release.yml` — header comment (lines 3–7), the concurrency comment (lines 23–24), a new `changes` job after `test`, the `release` job's `needs`/`if`/checkout (lines 44–49), the `Release notes` step (lines 293–324).
- Modify: `Packages/Core/Tests/StatusUITests/EveryReleaseListsItsChangesTests.swift` (add tests under `// MARK: the workflow`)

**Interfaces:**
- Consumes: `tools/release_notes.py changed` / `notes --tag --repository`.
- Produces: the job output `needs.changes.outputs.app`.

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run the suite to see the new tests fail**

Run: `cd Packages/Core && swift test --filter EveryReleaseListsItsChanges 2>&1 | tail -30`
Expected: the three workflow tests fail (`changes job` not found; `needs: test`; the notes step has no tool).

- [ ] **Step 3: Edit the workflow**

Header comment, replacing lines 3–7:

```yaml
# Every push to main that changes the app produces a downloadable build, and
# the release notes open with the commits that changed it. A push that changed
# nothing in the app — the site, the store listing, a tool — runs the tests and
# publishes nothing: the version number would move and the app would not, and
# the updater would offer everyone a download that changes nothing. The
# README link never has to change: GitHub keeps
# /releases/latest/download/<name> pointing at the newest release, so the
# workflow uploads the disk image twice — once under its version, once under a
# fixed name for that URL to resolve.
```

Concurrency comment, line 24: `commit. Queue them instead of cancelling: every push that changes the app deserves a build.`

After the `test` job, before `release`:

```yaml
  # Whether anything in the app changed since the previous release. The answer
  # comes from the tool that writes the release notes, so what is listed and
  # what is built are one question asked twice — a build that lists nothing
  # cannot happen by accident, and neither can a list nobody built.
  changes:
    name: What changed
    runs-on: ubuntu-latest
    outputs:
      app: ${{ steps.ask.outputs.changed }}
    steps:
      - uses: actions/checkout@v4
        with:
          # The previous release's tag, and the commits since it. The tool
          # refuses a shallow checkout rather than read it as "no release yet".
          fetch-depth: 0

      - name: Ask the tool
        id: ask
        run: |
          set -euo pipefail
          # Two statements, not `echo "changed=$(…)"`: a substitution that
          # fails inside an echo is an echo that succeeds, and the answer
          # written would be empty rather than the step failing.
          changed=$(python3 tools/release_notes.py changed)
          echo "changed=$changed" >> "$GITHUB_OUTPUT"
          echo "Something in the app changed since the previous release: $changed"
```

The `release` job's head:

```yaml
  release:
    name: Build and publish
    needs: [test, changes]
    # Only when something in the app changed — or on request, which is how a
    # rebuild is asked for: a new certificate, a re-notarisation. GitHub puts
    # success() in front of an `if` that names no status function, so a failed
    # test job still blocks this one.
    if: needs.changes.outputs.app == 'true' || github.event_name == 'workflow_dispatch'
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
        with:
          # The release notes are read from the history — see the changes job.
          fetch-depth: 0
```

The `Release notes` step, replacing its `run:` block:

```yaml
      - name: Release notes
        id: notes
        run: |
          set -euo pipefail
          # The list first. The Updates screen in the app shows the top of this
          # body in a box a few lines tall, and a checksum is not what somebody
          # deciding whether to update wants to read there.
          python3 tools/release_notes.py notes \
            --tag "${{ steps.v.outputs.tag }}" \
            --repository "${{ github.repository }}" > notes.md
          {
            echo
            echo "**Install** — open the disk image and drag Softcap to Applications."
            echo
            if [ "${{ steps.cert.outputs.signed }}" != "true" ]; then
              echo "This build is signed ad-hoc rather than with an Apple Developer ID,"
              echo "so macOS will refuse it on first launch. To open it anyway:"
              echo
              echo '```'
              echo 'xattr -dr com.apple.quarantine /Applications/Softcap.app'
              echo '```'
              echo
              echo "Or right-click the app, choose Open, and confirm once."
              echo
              echo "An ad-hoc signature is also new in every build, and the keychain"
              echo "binds access to the signature — so this version arrives unable to"
              echo "read the accounts the last one saved. Open Settings → Accounts and"
              echo "press **Open saved accounts** once; nothing is lost."
              echo
            fi
            echo "### Checksums"
            echo
            echo '```'
            cat dist/SHA256SUMS.txt
            echo '```'
          } >> notes.md
          cat notes.md
```

(The old first line, ``echo "Built from \`${GITHUB_SHA:0:7}\` on $(date -u '+%Y-%m-%d')."``, and the blank `echo` after it are gone — the tool prints that line.)

- [ ] **Step 4: Run the suite to see it pass, and check the YAML parses**

Run: `cd Packages/Core && swift test --filter EveryReleaseListsItsChanges 2>&1 | tail -20`
Expected: 12 tests pass.

Run: `python3 -c "import yaml" 2>/dev/null && python3 -c "import yaml,sys; d=yaml.safe_load(open('.github/workflows/release.yml')); print(list(d['jobs']), d['jobs']['release']['needs'])" || ruby -ryaml -e 'd=YAML.load_file(".github/workflows/release.yml"); p d["jobs"].keys, d["jobs"]["release"]["needs"]'`
Expected: `['test', 'changes', 'release'] ['test', 'changes']` (whichever parser the machine has).

Run: `python3 tools/release_notes.py notes --tag v0.1.99 --repository milushov/softcap`
Expected: the list now names this task's own commit-to-be? No — uncommitted changes are not commits. It still says `Nothing in the app changed since 0.1.36`; after the commit below, `release.yml` counts, and the first push will list "Build only what changed, and say what did" (or whatever the subject is).

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/release.yml Packages/Core/Tests/StatusUITests/EveryReleaseListsItsChangesTests.swift
git commit -m "Build only when the app changed, and open the release with what did"
```

---

### Task 4: The record

**Files:**
- Modify: `README.md:101-102`
- Modify: `docs/DECISIONS.md` (append after the last entry)
- Modify: `docs/superpowers/specs/2026-09-22-release-notes-design.md` — status line to `approved, implemented`

- [ ] **Step 1: The README sentence**

Replace:

```
The [release workflow](.github/workflows/release.yml) builds macOS on pushes to
`main` except documentation-only changes, then signs and packages a DMG and ZIP.
```

with:

```
The [release workflow](.github/workflows/release.yml) builds macOS on pushes to
`main` that change the app — the release notes list the commits that did — then
signs and packages a DMG and ZIP. A push that changes only the site, the store
listing or a tool runs the tests and publishes nothing.
```

- [ ] **Step 2: The decision**

Append to `docs/DECISIONS.md`, after the entry of 2026-09-21, separated by `---`:

```markdown
## 2026-09-22 — A release opens with what changed, and a push that changed nothing publishes nothing

**Decision.** The body of every GitHub release now opens with the subjects of
the commits since the previous release that touched what the disk image is
made of — `App/`, `Packages/` less its tests, `Widget/`, `Resources/`,
`project.yml`, `Signing.xcconfig`, the release workflow and the two scripts
that sign and package — oldest first, with `[skip ci]` trimmed and merge
commits left out; then the commit and the day, linking to everything since
the previous release. The same list decides whether there is a release at
all: a push in which no commit touched those paths runs the tests and
publishes nothing. A run started by hand always builds, and when nothing
changed its notes say so. `tools/release_notes.py` answers both questions,
and `EveryReleaseListsItsChanges` asks them in a repository it builds for
the purpose.

**Why.** Thirty-six releases, and not one said what was in it. The list was
already written — every subject in this repository is the sentence a reader
wants — and the pipeline was throwing it away and printing checksums, which
is also what the app's Updates screen showed to somebody deciding whether to
update. Reading the subjects out costs nothing to keep up; a changelog file
would have been the same sentence written twice, and at one or two commits a
release the second copy would have gone stale by the third release.

The gate came out of trying the list on the last seven releases: four of
them would have said "nothing in the app changed". They were the site, the
store listing and the screenshot tooling — pushes that moved the version
number, cost fifteen minutes of signing and notarisation, and had the updater
offer everyone a download identical to the one they had. What a commit
*touched* is the test, not how its subject reads: the commit that let the
staleness badge shrink touched the landing page's mock, and the release it
triggered was the app again.

**Cost.** A change to the store lane's own tooling — `asc_preflight.py`, the
export options — no longer exercises the TestFlight upload until the next
change to the app; a run started by hand does. Two full-history checkouts per
run instead of one shallow one, on a repository of forty megabytes. A commit
that mixed an app change with tooling is listed under its subject as written,
tooling flavour and all — the price of reading the list out rather than
writing it twice. And the past stays as it was: the thirty-six bodies already
published still say nothing, because the ask was for every future version.
```

- [ ] **Step 3: Mark the spec implemented**

In `docs/superpowers/specs/2026-09-22-release-notes-design.md`, change `**Status:** approved` to `**Status:** approved, implemented 2026-09-22`.

- [ ] **Step 4: Run the whole suite**

Run: `cd Packages/Core && swift test 2>&1 | tail -5`
Expected: every suite passes (the count was 647 tests in 122 suites before this work; now 12 more tests in one more suite).

- [ ] **Step 5: Commit**

```bash
git add README.md docs/DECISIONS.md docs/superpowers/specs/2026-09-22-release-notes-design.md docs/superpowers/plans/2026-09-22-release-notes.md
git commit -m "Record why a release says what changed, and why some pushes are no release"
```

---

## Self-review

- **Spec coverage.** What a release reads like → Task 2 (`notes`) and Task 3 (the step order). What is listed → Task 1's `THE_APP`/`NOT_THE_APP`, Task 2's tests. The gate → Task 1 (`changed`), Task 3 (`if:`). Shallow refusal → Task 1. `workflow_dispatch` always builds → Task 3's `if:`. `paths-ignore` untouched → no task edits it. Tests as listed in the spec → Tasks 1–3. Documents → Task 4. Not-in-scope items → no task.
- **Placeholders.** Task 1 defines `notes` as a `NotImplementedError` stub replaced in Task 2 — stated, not implied.
- **Names.** `Fixture.tool(_:)`, `.commit(_:touching:)`, `.tag(_:)`, `.merge(_:touching:)`, `.shallowClone()`, `.shortHead()`, `.discard()`, `Answer.status/out/err`, `Self.read(_:least:)`, `Self.job(_:in:)`, `Self.toolPath`; in Python `THE_APP`, `NOT_THE_APP`, `SKIP_CI`, `RELEASE_TAG`, `git`, `refuse_a_shallow_checkout`, `previous_release`, `version_of`, `changes_since`, `changed`, `notes`, `main` — used consistently across tasks.
