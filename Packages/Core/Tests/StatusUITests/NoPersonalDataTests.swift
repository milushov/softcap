import Testing
import Foundation

/// The guard on a rule learnt the hard way: no real personal data in the
/// repository.
///
/// Writing the legend code, the account list from the machine it was written on
/// went straight into a test, a doc comment and the decision log — three real
/// mail addresses, committed. They were caught by a person reading the diff, and
/// only because the repository has never been pushed was that in time.
///
/// Addresses in examples belong to the domains reserved for the purpose
/// (RFC 2606: `example.com`, `example.org`, `example.net`, and the `.test`,
/// `.example`, `.invalid` and `.localhost` suffixes). Anything else is a domain
/// somebody owns, and an address there is a claim about a real person.
@Suite struct NoPersonalDataInTheRepository {

    private static let reserved = [
        "example.com", "example.org", "example.net",
        ".example", ".test", ".invalid", ".localhost",
    ]

    /// Scanned by extension rather than by directory: a leak is as likely in a
    /// mock-up or a plan as in the sources.
    /// Every text file kind the repository has. It began as the seven a leak had
    /// happened in, and left out the four where the two most specific checks here
    /// look for their subject: an Apple team identifier and a bundle identifier
    /// live in `.entitlements`, `.plist` and `.xcconfig`, and none of those were
    /// read. `.sh` was missing too — a shell script is where a host address or a
    /// token gets pasted.
    /// Addresses in examples belong to the ranges reserved for documentation
    /// (RFC 5737) or to the private ones; anything else routes somewhere real.
    /// Shared, because the history is scanned for the same shape as the files.
    private static func isReservedAddress(_ address: String) -> Bool {
        let o = address.split(separator: ".").compactMap { Int($0) }
        guard o.count == 4, o.allSatisfy({ (0...255).contains($0) }) else { return true }
        switch (o[0], o[1], o[2]) {
        case (0, _, _), (10, _, _), (127, _, _):            return true  // this host, private
        case (169, 254, _), (192, 168, _):                  return true  // link-local, private
        case (172, 16...31, _):                             return true  // private
        case (192, 0, 2), (198, 51, 100), (203, 0, 113):    return true  // RFC 5737 docs
        case (224...255, _, _):                             return true  // multicast, broadcast
        default:                                            return false
        }
    }

    private static let extensions = [
        "swift", "py", "md", "strings", "yml", "json", "html",
        "sh", "plist", "entitlements", "xcconfig", "xml", "txt", "svg",
    ]

    @Test func exampleAddressesUseTheReservedDomains() throws {
        let pattern = "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        let regex = try NSRegularExpression(pattern: pattern)
        var offenders: [String] = []

        for file in try Self.textFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                guard let found = Range(match.range, in: text) else { continue }
                let address = String(text[found])
                let host = address.split(separator: "@").last.map(String.init) ?? ""
                let allowed = Self.reserved.contains { host == $0 || host.hasSuffix($0) }
                if !allowed {
                    offenders.append("\(file.lastPathComponent): \(address)")
                }
            }
        }

        #expect(offenders.isEmpty, """
            addresses outside the reserved example domains: \
            \(offenders.sorted().joined(separator: "; "))
            """)
    }

    /// The account identifiers this app deals in are UUIDs, and one pasted from
    /// a running instance names a real subscription.
    @Test func noAccountIdentifiersFromARunningInstance() throws {
        let pattern = "(claude|codex)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
        let regex = try NSRegularExpression(pattern: pattern)
        var offenders: [String] = []

        for file in try Self.textFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                guard let found = Range(match.range, in: text) else { continue }
                offenders.append("\(file.lastPathComponent): \(text[found])")
            }
        }
        #expect(offenders.isEmpty, "account identifiers: \(offenders.joined(separator: "; "))")
    }

    /// A token or an authorization code that reached a file would survive in the
    /// history even after being deleted from the working tree.
    @Test func noCredentialsInTheRepository() throws {
        let patterns = [
            "sk-ant-[A-Za-z0-9_-]{10,}",          // an Anthropic key
            "eyJ[A-Za-z0-9_-]{30,}",              // a JWT
            "\"refreshToken\"\\s*:\\s*\"[^\"]{20,}",
            "\"accessToken\"\\s*:\\s*\"[^\"]{20,}",
        ]
        var offenders: [String] = []

        for file in try Self.textFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            for pattern in patterns {
                let regex = try NSRegularExpression(pattern: pattern)
                let range = NSRange(text.startIndex..., in: text)
                if regex.firstMatch(in: text, range: range) != nil {
                    offenders.append("\(file.lastPathComponent) matches \(pattern)")
                }
            }
        }
        #expect(offenders.isEmpty, "credentials: \(offenders.joined(separator: "; "))")
    }

    /// A home directory names its owner, and a path from one machine does not
    /// work on another.
    @Test func noAbsolutePathsFromOneMachine() throws {
        var offenders: [String] = []
        for file in try Self.textFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            if let range = text.range(of: "/Users/[A-Za-z0-9._-]+/", options: .regularExpression) {
                offenders.append("\(file.lastPathComponent): \(text[range])")
            }
        }
        #expect(offenders.isEmpty, "home directories: \(offenders.joined(separator: "; "))")
    }

    /// The machine a thing was built on names its owner as surely as an address
    /// does. `Device "…" isn't registered` was pasted from a failing build into
    /// the decision log, and the name of this Mac travelled with it.
    ///
    /// Asked of the running system rather than written down, so the check keeps
    /// working on another machine instead of guarding one stale name.
    @Test func noNameOfTheMachineTheRepositoryIsWrittenOn() throws {
        var offenders: [String] = []
        for file in try Self.textFiles() {
            let text = try String(contentsOf: file, encoding: .utf8).lowercased()
            for name in Self.namesOfThisMachine() where text.contains(name) {
                offenders.append("\(file.lastPathComponent): \(name)")
            }
        }
        #expect(offenders.isEmpty, """
            this machine's name or user: \(offenders.sorted().joined(separator: "; "))
            """)
    }

    /// What this machine is called, when that names a person — and nothing at
    /// all on CI.
    ///
    /// A GitHub runner's user is literally named `runner`, and that word is
    /// ordinary prose in every file that describes the workflow: the first run
    /// after the repository was recreated failed on four of them for saying it.
    /// The subject of this check is the author's machine, and the author's
    /// machine is never the one CI provides — there the names identify nobody,
    /// so there is nothing true for the check to find. It keeps doing its work
    /// where the names are real: on the machine the repository is written on,
    /// in the pre-commit hook and in `make test`.
    static func namesOfThisMachine(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Set<String> {
        guard environment["CI"] == nil else { return [] }
        let host = ProcessInfo.processInfo.hostName
            .replacingOccurrences(of: ".local", with: "")
        // A name of three characters or fewer is as likely to be an ordinary
        // word in prose as an identifier, and a false failure teaches people to
        // pass --no-verify.
        return Set([host, NSUserName()].map { $0.lowercased() }.filter { $0.count > 3 })
    }

    /// A sibling checkout names a project that is not this one. The landing's
    /// deploy script pointed at another service's directory to explain a
    /// pattern, and named a second project on the same host to anyone reading.
    ///
    /// Which directories are siblings is asked of this checkout rather than
    /// written down: the workspace is whatever directory the repository sits in,
    /// so the check travels to a machine that arranges things differently.
    @Test func noPathsIntoOtherProjects() throws {
        let workspace = Self.repositoryRoot.deletingLastPathComponent().lastPathComponent
        let project = Self.repositoryRoot.lastPathComponent
        let escaped = NSRegularExpression.escapedPattern(for: workspace)

        let patterns = [
            "(?:~|\\$HOME|/Users/[^/\\s]+)/\(escaped)/([A-Za-z0-9._-]+)",
            "/opt/([A-Za-z0-9._-]+)",
        ]
        // This project, its deployment directory, and the placeholder the deploy
        // script uses where it has to point at a neighbour to explain a pattern.
        let ours: Set<String> = [project.lowercased(), "softcap-site", "another-site"]

        var offenders: [String] = []
        for file in try Self.textFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            for pattern in patterns {
                let regex = try NSRegularExpression(pattern: pattern)
                let range = NSRange(text.startIndex..., in: text)
                for match in regex.matches(in: text, range: range) {
                    guard let whole = Range(match.range, in: text),
                          let name = Range(match.range(at: 1), in: text) else { continue }
                    guard !ours.contains(String(text[name]).lowercased()) else { continue }
                    offenders.append("\(file.lastPathComponent): \(text[whole])")
                }
            }
        }
        #expect(offenders.isEmpty, """
            paths into other projects: \(offenders.sorted().joined(separator: "; "))
            """)
    }

    /// The address of a host somebody administers is an invitation. The landing
    /// deploy script carried `root@<address>` as its default until the domain
    /// became the thing that decides where the site lives.
    ///
    /// Addresses in examples belong to the ranges reserved for documentation
    /// (RFC 5737) or to the private ranges; anything else routes somewhere real.
    @Test func noAddressesOfRealHosts() throws {
        let regex = try NSRegularExpression(
            pattern: "(?<![0-9.])((?:[0-9]{1,3}\\.){3}[0-9]{1,3})(?![0-9.])")

        var offenders: [String] = []
        for file in try Self.textFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                guard let found = Range(match.range(at: 1), in: text) else { continue }
                let address = String(text[found])
                if !Self.isReservedAddress(address) {
                    offenders.append("\(file.lastPathComponent): \(address)")
                }
            }
        }
        #expect(offenders.isEmpty, """
            addresses of real hosts: \(offenders.sorted().joined(separator: "; "))
            """)
    }

    /// A team identifier prefixes every app-group container, so documenting the
    /// path documents the developer account. It is not a secret — it ships in
    /// every signed build — but it is an account this repository need not name.
    /// A bundle identifier for this project begins with `app.softcap`.
    ///
    /// The history rewrite replaced the old prefix — built from a personal
    /// domain — 1450 times, and put `dev.example.…` in its place wherever an
    /// entry had to quote it. Then an entry written the same week quoted a stale
    /// widget registration verbatim and wrote the real one straight back in. The
    /// eight checks in this suite had no opinion about it: the rewrite cleaned
    /// the past and nothing was watching the present.
    ///
    /// Stated as a shape rather than a value, so this file does not have to
    /// contain the thing it forbids — the same reason two of the checks above
    /// ask the running system instead of storing an answer.
    @Test func everyBundleIdentifierIsThisProjects() throws {
        let allowed = ["app.softcap", "dev.example"]
        let pattern = #"[a-z][a-z0-9-]*(?:\.[a-z][a-z0-9-]*)+\.(?:Softcap|StatusChecker)\b"#
        let regex = try NSRegularExpression(pattern: pattern)

        var offenders: [String] = []
        for file in try Self.textFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                guard let found = Range(match.range, in: text).map({ String(text[$0]) })
                else { continue }
                // An app group is the same identifier with `group.` in front,
                // and the redacted historical ones appear in both forms.
                let bare = found.hasPrefix("group.")
                    ? String(found.dropFirst("group.".count)) : found
                if allowed.contains(where: { bare.hasPrefix($0 + ".") }) { continue }
                offenders.append("\(file.lastPathComponent): \(found)")
            }
        }
        #expect(offenders.isEmpty, """
            a bundle identifier that is not this project's: \
            \(Array(Set(offenders)).sorted().joined(separator: "; ")) — \
            quote `dev.example.…` when an entry has to mention the old one
            """)
    }

    @Test func noAppleTeamIdentifier() throws {
        // Two shapes. The first is ten upper-case alphanumerics in front of an app
        // group — a team prefix wherever a container path is written out.
        //
        // The second is where one is actually typed: `DEVELOPMENT_TEAM = …` in an
        // xcconfig. That file is tracked, the local one beside it is not, and
        // pasting into the wrong one is a single keystroke. Until the walk was
        // widened to read `.xcconfig` at all this could not have fired; now that
        // it can, it should look for the form it would arrive in.
        let patterns = ["\\b([A-Z0-9]{10})\\.group\\.",
                        "DEVELOPMENT_TEAM\\s*=\\s*([A-Z0-9]{10})\\b"]
        // `YYYYYYYYYY` is what Signing.xcconfig uses to show the shape.
        let placeholders = ["ABCDE12345", "YYYYYYYYYY"]

        var offenders: [String] = []
        for file in try Self.textFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for pattern in patterns {
                for match in try NSRegularExpression(pattern: pattern)
                    .matches(in: text, range: range) {
                    guard let found = Range(match.range(at: 1), in: text) else { continue }
                    let team = String(text[found])
                    if !placeholders.contains(team) {
                        offenders.append("\(file.lastPathComponent): \(team)")
                    }
                }
            }
        }
        #expect(offenders.isEmpty, """
            team identifiers (use \(placeholders[0]) in documentation): \
            \(offenders.sorted().joined(separator: "; "))
            """)
    }

    // MARK: - the history, which the walk above cannot see

    /// The nine checks above read files. A value that reached a commit message
    /// is in none of them.
    ///
    /// The bundle prefix this project used before it was renamed was built from
    /// a personal domain. A rewrite of the whole history replaced it 1450 times,
    /// and it is described here rather than written out, for the reason this
    /// check exists. It came back twice in the week after that rewrite: once
    /// into an entry quoting
    /// `pluginkit` output verbatim, and once into the body of a merge commit
    /// describing what the rename had broken. The entry was fixed the same day
    /// and every check above went quiet again. The message was not, because
    /// nothing here had ever read one — and a message cannot be fixed forward,
    /// since editing it rewrites every commit after it.
    ///
    /// Asked of git rather than of the working tree, so this sees what a clone
    /// sees rather than what happens to be checked out.
    @Test func noPersonalDataInCommitMessages() throws {
        var offenders: [String] = []
        for commit in try Self.commitMessages() {
            for finding in try Self.privateShapes(in: commit.body) {
                offenders.append("\(commit.name.prefix(9)): \(finding)")
            }
        }
        #expect(offenders.isEmpty, """
            personal data in commit messages, which no later commit can remove: \
            \(offenders.sorted().joined(separator: "; "))
            """)
    }

    // MARK: - walking the repository

    /// Every text file in the repository, skipping what is not committed:
    /// build products, the package checkout, and the local signing settings.
    ///
    /// `.claude` is skipped because the agent harness keeps git worktrees there
    /// — whole checkouts of this repository at other commits. Walking into one
    /// reports its files as if they were these, which reads as a leak that has
    /// already been fixed here and merely still exists on another branch.
    /// A check that examined nothing is a check that passed.
    ///
    /// Every test in this suite walks this list and asserts that what it found
    /// is empty. If the walk itself came back empty — a moved directory, a
    /// `#filePath` that resolves elsewhere in another build layout, a skip-list
    /// that grew a `.` too many — all nine would report success having read no
    /// file at all. Proved by making this return `[]`: 338 tests passed, and the
    /// commit hook that runs this suite would have approved anything.
    ///
    /// So the floor is here rather than in each caller. The repository has
    /// roughly 170 files of these kinds; fifty is far below any honest count and
    /// far above zero.
    private static let fewestPlausibleFiles = 50

    enum ScanFailed: Error, CustomStringConvertible {
        case tooFewFiles(found: Int, expected: Int)
        case noHistory
        var description: String {
            switch self {
            case .noHistory:
                "the personal-data scan read no commit message at all — git answered with "
                + "nothing, and the check on the history would otherwise have passed having "
                + "read none"
            case let .tooFewFiles(found, expected):
                "the personal-data scan found \(found) files, fewer than the \(expected) "
                + "this repository has — it is looking in the wrong place, and every check "
                + "in this suite would otherwise have passed without reading anything"
            }
        }
    }

    private static func textFiles() throws -> [URL] {
        let found = try walkTextFiles()
        guard found.count >= fewestPlausibleFiles else {
            throw ScanFailed.tooFewFiles(found: found.count, expected: fewestPlausibleFiles)
        }
        return found
    }

    private static func walkTextFiles() throws -> [URL] {
        let skipped = [
            ".build", ".git", ".claude", "build", "build-ios", "DerivedData", ".swiftpm",
        ]
        guard let walker = FileManager.default.enumerator(
            at: repositoryRoot, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        var found: [URL] = []
        for case let url as URL in walker {
            if skipped.contains(url.lastPathComponent) {
                walker.skipDescendants()
                continue
            }
            guard extensions.contains(url.pathExtension) else { continue }
            guard url.lastPathComponent != "Signing.local.xcconfig" else { continue }
            // This file states the shapes the others must not contain; scanning
            // it reports every pattern as a finding against itself.
            guard url.lastPathComponent != URL(fileURLWithPath: #filePath).lastPathComponent
            else { continue }
            found.append(url)
        }
        return found
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)      // …/Packages/Core/Tests/StatusUITests/<file>.swift
            .deletingLastPathComponent()      // …/Tests/StatusUITests
            .deletingLastPathComponent()      // …/Tests
            .deletingLastPathComponent()      // …/Core
            .deletingLastPathComponent()      // …/Packages
            .deletingLastPathComponent()      // repository root
    }

    // MARK: - reading the history

    /// Every commit message in the repository, with the commit it belongs to.
    ///
    /// The floor is the same idea as `fewestPlausibleFiles` above: git answering
    /// with nothing — run outside a checkout, or in one with no commits yet —
    /// would let the check pass having read no message at all.
    private static func commitMessages() throws -> [(name: String, body: String)] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [
            "-C", repositoryRoot.path, "log", "--all", "--format=%H%x1f%B%x1e",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Read before waiting: a history larger than the pipe buffer would
        // otherwise block git on a write nobody is draining.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8)
        else { throw ScanFailed.noHistory }

        let found: [(name: String, body: String)] = text
            .components(separatedBy: "\u{1e}")
            .compactMap { record in
                let parts = record.components(separatedBy: "\u{1f}")
                guard parts.count == 2 else { return nil }
                let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                return (name: name, body: parts[1])
            }
        guard !found.isEmpty else { throw ScanFailed.noHistory }
        return found
    }

    /// The shapes the checks above look for, asked of one piece of text rather
    /// than of a file — so the history can be held to the same rules.
    private static func privateShapes(in text: String) throws -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        func matches(_ pattern: String, _ group: Int = 0) throws -> [String] {
            try NSRegularExpression(pattern: pattern)
                .matches(in: text, range: range)
                .compactMap { Range($0.range(at: group), in: text).map { String(text[$0]) } }
        }
        var found: [String] = []

        for address in try matches("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}") {
            let host = address.split(separator: "@").last.map(String.init) ?? ""
            if !reserved.contains(where: { host == $0 || host.hasSuffix($0) }) {
                found.append("mail address \(address)")
            }
        }

        for id in try matches(
            "(?:claude|codex)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
        ) {
            found.append("account identifier \(id)")
        }

        for pattern in ["sk-ant-[A-Za-z0-9_-]{10,}", "eyJ[A-Za-z0-9_-]{30,}"] {
            let hits = try matches(pattern)
            if !hits.isEmpty { found.append("a credential shape") }
        }

        // A home directory names its owner. An elided one — `/Users/…/` — is how
        // such a path gets written down on purpose, and names nobody.
        for name in try matches("/Users/([^/\\s]+)/", 1)
        where name.contains(where: { $0.isLetter || $0.isNumber }) {
            found.append("home directory /Users/\(name)/")
        }

        let lowered = text.lowercased()
        for name in namesOfThisMachine() where lowered.contains(name) {
            found.append("this machine's name or login")
        }

        for id in try matches(
            #"[a-z][a-z0-9-]*(?:\.[a-z][a-z0-9-]*)+\.(?:Softcap|StatusChecker)\b"#
        ) {
            let bare = id.hasPrefix("group.") ? String(id.dropFirst("group.".count)) : id
            if !["app.softcap", "dev.example"].contains(where: { bare.hasPrefix($0 + ".") }) {
                found.append("bundle identifier \(id)")
            }
        }

        for team in try matches("\\b([A-Z0-9]{10})\\.group\\.", 1)
        where !["ABCDE12345", "YYYYYYYYYY"].contains(team) {
            found.append("team identifier \(team)")
        }

        for address in try matches("(?<![0-9.])((?:[0-9]{1,3}\\.){3}[0-9]{1,3})(?![0-9.])", 1)
        where !isReservedAddress(address) {
            found.append("host address \(address)")
        }

        return found
    }
}
