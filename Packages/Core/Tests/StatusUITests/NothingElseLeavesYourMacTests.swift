import Testing
import Foundation

/// The landing makes a promise about the reader's machine: "Credentials stay in
/// the keychain, never copied into preferences or logs. No telemetry. The only
/// other request is a daily check for a new version, and it can be switched
/// off."
///
/// It read "nothing else leaves your Mac" until the updater made that untrue.
/// `thePageStillMakesThePromise` checks the two phrases the suite actually
/// guards, so it kept passing across the rewrite — correctly, but this comment
/// went on quoting a sentence nobody could find.
///
/// Every other claim on that page is about a feature, and a feature that stops
/// working is visible. This one is about an absence, and an absence stops being
/// true silently — one convenient line adding a crash reporter, one field on a
/// settings struct, one `log.error` that interpolates a token while somebody is
/// chasing a sign-in bug. Nobody would notice, and the page would go on saying
/// it in confident English.
///
/// So the promise is checked the way the numbers on the page are: the code still
/// has the property, and the page still claims it. Changing either alone fails.
@Suite struct NothingElseLeavesYourMac {

    /// Hosts, not requests. A string is not proof that anything is fetched —
    /// `https://api.openai.com/auth` in this codebase is the namespace of a
    /// claim *inside* a Codex token, and `www.apple.com` in the plists is a DTD
    /// declaration nobody has resolved since 2003. The point is not to catch a
    /// request; it is that adding a host you have to name here is the moment to
    /// notice you are adding one.
    @Test func everyHostIsOneWeNamed() throws {
        // Each entry is a promise-sized decision, so each carries its reason.
        let named: [String: String] = [
            "api.anthropic.com":   "the Claude usage endpoint — the one live request",
            "platform.claude.com": "OAuth authorize and token, and the manual redirect",
            "claude.com":          "where the sign-in flow sends the browser",
            "api.openai.com":      "not fetched: the namespace of a claim inside a Codex token",
            "localhost":           "the loopback the PKCE redirect comes back to",
            "api.github.com":      "the release feed, once a day, and switchable off",
            "github.com":          "the release page, and the build a release publishes",
        ]

        let files = try Self.swiftFiles()
        guard files.count >= 40 else {
            throw ScanIsLookingInTheWrongPlace(what: "source", found: files.count, least: 40)
        }

        var seen: [String: String] = [:]      // host -> first file naming it
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for host in Self.hosts(in: text) where seen[host] == nil {
                seen[host] = file.lastPathComponent
            }
        }

        // Vacuous otherwise: a regex that matches nothing approves everything.
        guard seen.count >= 4 else {
            throw ScanIsLookingInTheWrongPlace(what: "host", found: seen.count, least: 4)
        }

        for (host, file) in seen.sorted(by: { $0.key < $1.key }) {
            #expect(named[host] != nil, """
                \(file) names the host \(host), which this test does not know about. \
                The landing promises nothing else leaves the reader's Mac. If that is \
                still true, add \(host) here with the reason it is there; if it is not, \
                the page needs changing, not this list.
                """)
        }
    }

    /// One door. Every provider, the login flow and the credential store take an
    /// `HTTPClient` and none of them builds a request, so there is exactly one
    /// place in the project where a URL becomes traffic. That is what makes the
    /// host list above worth reading: a second builder could reach a host this
    /// scan never sees, assembled from pieces.
    @Test func oneTypeBuildsEveryRequest() throws {
        let builders = try Self.swiftFiles()
            .filter { try String(contentsOf: $0, encoding: .utf8).contains("URLRequest(") }
            .map(\.lastPathComponent)
            .sorted()

        #expect(builders == ["HTTPClient.swift"], """
            \(builders.count) files build a URLRequest: \(builders.joined(separator: ", ")). \
            There was one, and the single door is what the host check leans on.
            """)
    }

    /// Settings are written to disk in the clear, in a plist anybody can read.
    /// The keychain exists so credentials are not there, and a field is the
    /// easiest way to undo that by accident — `refreshToken` on a settings
    /// struct looks exactly like the other twenty when you are reading a diff.
    ///
    /// "Key" is not on the list on purpose: two settings are hot keys, and a
    /// check that has to be argued with every time is a check somebody deletes.
    @Test func noSettingIsACredential() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot
                .appendingPathComponent("Packages/Core/Sources/Preferences/Preferences.swift"),
            encoding: .utf8
        )
        let fields = Self.matches(#"var ([a-zA-Z]+):"#, in: source)
        guard fields.count >= 15 else {
            throw ScanIsLookingInTheWrongPlace(what: "settings field", found: fields.count, least: 15)
        }

        for word in ["token", "secret", "password", "credential"] {
            let offenders = fields.filter { $0.lowercased().contains(word) }
            #expect(offenders.isEmpty, """
                a setting is named \(offenders.joined(separator: ", ")) — settings are \
                written to a plist in the clear, and the landing says credentials stay \
                in the keychain
                """)
        }
    }

    /// The other half of the same sentence. The log is the second place a secret
    /// leaks to, and `privacy: .public` is what makes it readable — the default
    /// redacts. Eleven lines use it, all of them for account identifiers and
    /// counts, which is what makes them worth logging at all.
    @Test func nothingSecretIsLoggedInTheClear() throws {
        var offenders: [String] = []
        var publicInterpolations = 0
        for file in try Self.swiftFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.split(separator: "\n") where line.contains("privacy: .public") {
                publicInterpolations += 1
                let lower = line.lowercased()
                if ["token", "secret", "password", "apikey"].contains(where: lower.contains) {
                    offenders.append("\(file.lastPathComponent): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        guard publicInterpolations >= 5 else {
            throw ScanIsLookingInTheWrongPlace(
                what: "public log interpolation", found: publicInterpolations, least: 5)
        }
        #expect(offenders.isEmpty, """
            a log line writes something credential-shaped unredacted: \
            \(offenders.joined(separator: " / "))
            """)
    }

    /// If the page stops promising it, these checks are guarding nothing and
    /// should say so rather than passing quietly for another year.
    @Test func thePageStillMakesThePromise() throws {
        #expect(try Self.pageSays("Credentials stay in the keychain"),
                "the landing no longer makes the claim this suite is guarding")
        #expect(try Self.pageSays("No telemetry"),
                "the landing no longer makes the claim this suite is guarding")
    }

    // MARK: -

    private static func hosts(in text: String) -> Set<String> {
        Set(matches(#"https?://([a-zA-Z0-9.-]+)"#, in: text))
    }

    /// First capture group of every match.
    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let whole = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: whole).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    /// Production sources only: this file names every host it allows, and would
    /// find itself.
    private static func swiftFiles() throws -> [URL] {
        let skipped = [".build", ".git", ".claude", "build", "build-ios", "DerivedData", "Tests"]
        guard let walker = FileManager.default.enumerator(
            at: repositoryRoot, includingPropertiesForKeys: nil
        ) else { return [] }
        var found: [URL] = []
        for case let url as URL in walker {
            if skipped.contains(url.lastPathComponent) { walker.skipDescendants(); continue }
            if url.pathExtension == "swift" { found.append(url) }
        }
        return found
    }

    /// Takes the phrase, not the page: see `HowToAskADocument`.
    private static func pageSays(_ phrase: String) throws -> Bool {
        let text = try String(
            contentsOf: repositoryRoot.appendingPathComponent("site/index.html"), encoding: .utf8)
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ").says(phrase)
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
