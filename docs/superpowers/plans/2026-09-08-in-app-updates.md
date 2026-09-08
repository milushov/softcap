# In-app updates — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Softcap finds a newer release on GitHub, downloads it, verifies it, replaces itself and restarts — without opening a window uninvited.

**Architecture:** A new `Updates` product in `Packages/Core` holds the pure pieces (version comparison, feed decoding, checksum lookup, the check schedule) and one impure one (`UpdateInstaller`). It is not listed among the iOS target's dependencies, the same arrangement `CodexProvider` has. The interface lives entirely inside the settings window that already exists: a new sidebar screen, a footer, and two menu items. No sheet, no second window.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing (`@Suite` / `@Test` / `#expect`), SwiftPM for the logic package, xcodegen for the app project. No external dependencies.

## Global Constraints

- **Documentation in English.** README, decision log, specs, plans, code comments. Conversation with the author is Russian; nothing in the repository is.
- **No human-facing strings in `Packages/Core`.** Models return identifiers and numbers. `UpdateFailure.kind` is an identifier; the sentence is assembled by the interface. Enforced by `CoreHasNoHumanStrings`.
- **Every new interface string goes into all ten catalogues** via `tools/add_strings.py`, which reads JSON on stdin. Languages: `en zh-Hans hi es ar fr bn pt-BR ru id`. A key present in the catalogues and used nowhere fails `NoOrphanStrings`; a key used and absent shows in English. So strings land in the same commit as the view that uses them.
- **One file builds every `URLRequest`.** `NothingElseLeavesYourMac.oneTypeBuildsEveryRequest` asserts the list is exactly `["HTTPClient.swift"]`. New network code goes in that file.
- **Every host is named.** `NothingElseLeavesYourMac.everyHostIsOneWeNamed` scans production Swift for `https?://([a-zA-Z0-9.-]+)` and refuses a host absent from its dictionary.
- **The landing keeps its promise.** `thePageStillMakesThePromise` requires `site/index.html` to say "Credentials stay in the keychain" and "No telemetry". Both survive the rewrite in Task 6.
- **No macOS-only import outside `#if os(macOS)`** in `Packages/Core`, and no `import AppKit` at all. `Security` is not on that list and needs no guard.
- **No run of three or more spaces inside any catalogue line, logged sentence, or `#expect` message.** `SentencesReadAsSentences`.
- **Decisions are logged.** `docs/DECISIONS.md`, three parts: what was decided, why, what it cost. Entries are never rewritten.
- **Commit messages carry no session link and no agent trailer.** The message ends on its last line of real content.
- **Never `rm`.** Use `~/.claude/bin/ctrash <path>` with literal paths.
- **Repository:** `github.com/milushov/softcap`. Release assets: `Softcap-<version>.dmg`, `Softcap-<version>.zip`, `Softcap.dmg`, `SHA256SUMS.txt`. Tags are `v<version>`.
- **Test command:** `make test` (wraps `cd Packages/Core && swift test` with a stale-build retry). A single suite: `cd Packages/Core && swift test --filter <SuiteName>`.
- **Build command:** `make build`. Requires `Signing.local.xcconfig`; unsigned fallback is in the README.

---

## File Structure

**Created**

| Path | Responsibility |
|---|---|
| `Packages/Core/Sources/Updates/ReleaseVersion.swift` | parse and order `0.1.42` / `v0.1.42` |
| `Packages/Core/Sources/Updates/UpdateFailure.swift` | the identifiers a failure can be |
| `Packages/Core/Sources/Updates/Checksums.swift` | read `SHA256SUMS.txt`, look a name up |
| `Packages/Core/Sources/Updates/UpdateSchedule.swift` | whether a check is due, at an explicit moment |
| `Packages/Core/Sources/Updates/Release.swift` | one release: version, notes, archive, sums |
| `Packages/Core/Sources/Updates/ReleaseFeed.swift` | decode the GitHub releases response |
| `Packages/Core/Sources/Updates/UpdateInstaller.swift` | verify, unpack, replace, restart |
| `Packages/Core/Tests/UpdatesTests/ReleaseVersionTests.swift` | |
| `Packages/Core/Tests/UpdatesTests/ChecksumsTests.swift` | |
| `Packages/Core/Tests/UpdatesTests/UpdateScheduleTests.swift` | |
| `Packages/Core/Tests/UpdatesTests/ReleaseFeedTests.swift` | |
| `Packages/Core/Tests/UpdatesTests/UpdateInstallerTests.swift` | behavioural guards |
| `Packages/Core/Tests/StatusUITests/TheAppKnowsItsOwnVersionTests.swift` | project.yml guard |
| `Packages/Core/Tests/StatusUITests/AskingWhetherToCheckRequiresAMomentTests.swift` | no defaulted `now` |
| `App/UpdateModel.swift` | the check and the install, as app state |
| `App/Settings/UpdatesPane.swift` | *replaced content* — the new Updates screen |
| `App/Settings/PollingPane.swift` | the old pane, renamed |

**Modified**

| Path | Change |
|---|---|
| `project.yml:43` | `CFBundleShortVersionString: "$(MARKETING_VERSION)"`, add `CFBundleVersion` |
| `Packages/Core/Package.swift` | the `Updates` product, target and test target |
| `Packages/Core/Sources/ClaudeProvider/HTTPClient.swift` | `FileDownloader` and its implementation |
| `Packages/Core/Sources/Preferences/Preferences.swift` | `checksForUpdates`, `lastUpdateCheck` |
| `Packages/Core/Tests/StatusUITests/NothingElseLeavesYourMacTests.swift` | two hosts, with reasons |
| `site/index.html:609-610` | the privacy sentence |
| `App/Settings/SettingsIcons.swift` | `.polling` beside `.updates` |
| `App/Settings/SettingsView.swift` | the footer, the new case |
| `App/AppModel.swift` | `settingsSection` |
| `App/StatusItemController.swift` | version header, update item |
| `App/SoftcapApp.swift` | build and hold the `UpdateModel` |
| `Packages/Core/Sources/StatusUI/Resources/*.lproj/Localizable.strings` | ten catalogues |
| `docs/DECISIONS.md` | one entry |
| `README.md` | a paragraph on updating |

---

### Task 1: The app knows its own version

`project.yml` writes `CFBundleShortVersionString` as the literal `"0.1"` on the app target while the widget beside it uses `$(MARKETING_VERSION)`. The release workflow passes `MARKETING_VERSION=0.1.<run>` on the command line, so the widget follows it and the app does not — every published build calls itself `0.1`. `CFBundleVersion` is not set at all, which is why the About screen shows a bare `1`.

This is a bug without the feature, so it lands alone.

**Files:**
- Modify: `project.yml:43`
- Create: `Packages/Core/Tests/StatusUITests/TheAppKnowsItsOwnVersionTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: nothing in code. Every later task assumes `Bundle.main.infoDictionary["CFBundleShortVersionString"]` is the real version.

- [ ] **Step 1: Write the failing test**

Create `Packages/Core/Tests/StatusUITests/TheAppKnowsItsOwnVersionTests.swift`:

```swift
import Testing
import Foundation

/// The updater compares the running version against the newest release, so an
/// app that misreports its own version is permanently out of date and says so
/// forever.
///
/// It did. `project.yml` set `CFBundleShortVersionString` as a literal on the
/// app target while the widget beside it used `$(MARKETING_VERSION)`, and the
/// release workflow passes the version on the command line — so the widget
/// followed it and the app did not. Nothing depended on the number before, which
/// is the only reason it cost nothing.
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
    @Test func theBuildNumberIsSetAsWell() throws {
        let text = try String(contentsOf: Self.projectFile, encoding: .utf8)
        #expect(text.contains("CFBundleVersion:"), """
            no target sets CFBundleVersion, so every bundle carries Xcode's default \
            and the About screen shows it
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
```

`ScanIsLookingInTheWrongPlace` already exists in `Packages/Core/Tests/StatusUITests/ReadingProse.swift` — do not redeclare it.

- [ ] **Step 2: Run it and watch it fail**

```bash
cd Packages/Core && swift test --filter TheAppKnowsItsOwnVersion
```

Expected: `everyBundleTakesItsVersionFromTheBuildSetting` fails naming `0.1`, twice (the Softcap target and the two iOS targets). `theBuildNumberIsSetAsWell` fails.

- [ ] **Step 3: Fix the project description**

In `project.yml`, the `Softcap` target's `info.properties` currently reads:

```yaml
      properties:
        LSUIElement: true
        CFBundleName: Softcap
        CFBundleShortVersionString: "0.1"
```

Replace the last line, and add the build number:

```yaml
      properties:
        LSUIElement: true
        CFBundleName: Softcap
        # Taken from the build setting rather than written out: the release
        # workflow passes MARKETING_VERSION on the command line, and a literal
        # here ignores it — which is how every published build came to call
        # itself 0.1 while the widget beside it carried the real number.
        CFBundleShortVersionString: "$(MARKETING_VERSION)"
        CFBundleVersion: "$(MARKETING_VERSION)"
```

Do the same for the `SoftcapiOS` and `SoftcapiOSWidget` targets, which have no `CFBundleShortVersionString` entry at all today — add both keys to each, under their existing `info.properties`. The `SoftcapWidget` target already uses `$(MARKETING_VERSION)`; add `CFBundleVersion: "$(MARKETING_VERSION)"` beside it.

- [ ] **Step 4: Run the test and the build**

```bash
cd Packages/Core && swift test --filter TheAppKnowsItsOwnVersion
```
Expected: PASS.

```bash
make build && /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  build/Build/Products/Debug/Softcap.app/Contents/Info.plist
```
Expected: `0.1` — the value of `MARKETING_VERSION` in `project.yml`, now arriving through the setting. Confirm it moves by building with an override:

```bash
xcodebuild -project Softcap.xcodeproj -scheme Softcap -configuration Debug \
  -derivedDataPath build MARKETING_VERSION=9.9.9 build >/dev/null 2>&1
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  build/Build/Products/Debug/Softcap.app/Contents/Info.plist
```
Expected: `9.9.9`. This is the check that matters — it is the exact thing the release workflow does.

- [ ] **Step 5: Run the whole suite**

```bash
make test
```
Expected: PASS, one test more than before.

- [ ] **Step 6: Commit**

```bash
git add project.yml Packages/Core/Tests/StatusUITests/TheAppKnowsItsOwnVersionTests.swift
git commit -F - <<'MSG'
build: the app takes its version from the build setting

project.yml wrote CFBundleShortVersionString as a literal on the app target
while the widget beside it used $(MARKETING_VERSION). The release workflow
passes MARKETING_VERSION on the command line, so the widget followed it and
the app did not: every published build called itself 0.1.

Nothing read the number, which is the only reason it cost nothing. An
updater reads it to decide whether it is out of date, and would have been
told yes forever.

CFBundleVersion was not set on any target either — that is the bare 1 the
About screen has been showing.
MSG
```

---

### Task 2: The Updates module, and version ordering

**Files:**
- Modify: `Packages/Core/Package.swift`
- Create: `Packages/Core/Sources/Updates/ReleaseVersion.swift`
- Create: `Packages/Core/Sources/Updates/UpdateFailure.swift`
- Test: `Packages/Core/Tests/UpdatesTests/ReleaseVersionTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `ReleaseVersion.init?(_ text: String)` — accepts `0.1.42` and `v0.1.42`
  - `ReleaseVersion: Comparable, Hashable, Sendable, CustomStringConvertible`
  - `ReleaseVersion.description: String` — the text it was made from, without `v`
  - `UpdateFailure(kind:diagnostic:)` with `Kind`: `.network`, `.malformedRelease`, `.checksumMismatch`, `.signatureChanged`, `.notWritable`, `.unpackFailed`

- [ ] **Step 1: Add the target to the package**

In `Packages/Core/Package.swift`, add to `products`:

```swift
        .library(name: "Updates", targets: ["Updates"]),
```

to `targets`:

```swift
        .target(name: "Updates", dependencies: ["ProviderKit", "ClaudeProvider"]),
```

and to the test targets:

```swift
        .testTarget(name: "UpdatesTests", dependencies: ["Updates"]),
```

`ClaudeProvider` is a dependency because it owns `HTTPClient` — the one file in the project that builds a request. `Credentials` depends on it for the same reason.

- [ ] **Step 2: Write the failing test**

Create `Packages/Core/Tests/UpdatesTests/ReleaseVersionTests.swift`:

```swift
import Testing
import Foundation
@testable import Updates

@Suite struct ReleaseVersionOrdering {

    private func version(_ text: String) throws -> ReleaseVersion {
        try #require(ReleaseVersion(text), "\(text) did not parse")
    }

    /// The case the whole type exists for. Sorting these as text puts 0.1.10
    /// before 0.1.9, and the app would offer an update backwards on the tenth
    /// release after a nine.
    @Test func tenComesAfterNine() throws {
        #expect(try version("0.1.9") < version("0.1.10"))
    }

    @Test func tagsAndBundlesSpellTheSameVersion() throws {
        #expect(try version("v0.1.42") == version("0.1.42"))
    }

    /// The bundle says 0.1 before a release has ever set the run number, and a
    /// tag would say 0.1.0. They are the same version and neither is an update
    /// to the other.
    @Test func aTrailingZeroIsNotADifferentVersion() throws {
        #expect(try version("0.1") == version("0.1.0"))
        #expect(try version("0.1.0.0") == version("0.1"))
        #expect(try !(version("0.1") < version("0.1.0")))
    }

    @Test func moreComponentsCanStillBeNewer() throws {
        #expect(try version("0.1") < version("0.1.1"))
        #expect(try version("1.0") > version("0.99.99"))
    }

    @Test func zeroIsAVersion() throws {
        #expect(try version("0") == version("0.0.0"))
    }

    @Test func whatIsNotAVersionIsRefused() {
        #expect(ReleaseVersion("") == nil)
        #expect(ReleaseVersion("v") == nil)
        #expect(ReleaseVersion("0.1.x") == nil)
        #expect(ReleaseVersion("0.1-beta") == nil)
        #expect(ReleaseVersion("-1.0") == nil)
        #expect(ReleaseVersion("0..1") == nil)
    }

    /// The `v` is a tag's habit, not part of the number, and the interface
    /// shows the number.
    @Test func itReadsBackWithoutTheTagPrefix() throws {
        #expect(try version("v0.1.42").description == "0.1.42")
        #expect(try version("0.1.42").description == "0.1.42")
    }

    /// Equal versions hash equally, or a `Set` of them holds both spellings.
    @Test func twoSpellingsOfOneVersionAreOneElement() throws {
        let set: Set<ReleaseVersion> = try [version("0.1"), version("0.1.0"), version("v0.1")]
        #expect(set.count == 1)
    }
}
```

- [ ] **Step 3: Run it and watch it fail**

```bash
cd Packages/Core && swift test --filter ReleaseVersionOrdering
```
Expected: FAIL — `cannot find 'ReleaseVersion' in scope`.

- [ ] **Step 4: Write the implementation**

Create `Packages/Core/Sources/Updates/ReleaseVersion.swift`:

```swift
import Foundation

/// A released version, as a number rather than as text.
///
/// Releases are tagged `v0.1.42` and the bundle carries `0.1.42`; both spellings
/// are the same version. Comparison is component by component and numeric,
/// because the text form sorts `0.1.10` before `0.1.9` and the app would offer
/// an update backwards on the tenth release after a ninth.
///
/// Trailing zeros are dropped on the way in, so `0.1` and `0.1.0` are one
/// version and not two — the bundle says the first before a release has set a
/// run number and a tag would say the second.
public struct ReleaseVersion: Sendable, Hashable, Comparable, CustomStringConvertible {

    /// Significant components, most significant first, with trailing zeros
    /// removed. Never empty.
    private let components: [Int]

    /// The text it was made from, without a tag's `v`.
    public let description: String

    public init?(_ text: String) {
        let body = text.hasPrefix("v") ? String(text.dropFirst()) : text
        guard !body.isEmpty else { return nil }

        var numbers: [Int] = []
        for part in body.split(separator: ".", omittingEmptySubsequences: false) {
            // `Int("-1")` parses, and a negative component is not a version.
            // `Int("")` does not, which is what refuses `0..1`.
            guard let number = Int(part), number >= 0 else { return nil }
            numbers.append(number)
        }

        while numbers.count > 1, numbers.last == 0 { numbers.removeLast() }
        components = numbers
        description = body
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        let width = max(lhs.components.count, rhs.components.count)
        for index in 0..<width {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    // Synthesised conformances would compare and hash `description` as well,
    // and `0.1` would then differ from `0.1.0` in a dictionary while comparing
    // equal — which is the shape of bug that survives every test but one.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.components == rhs.components
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(components)
    }
}
```

- [ ] **Step 5: Run the test**

```bash
cd Packages/Core && swift test --filter ReleaseVersionOrdering
```
Expected: PASS, nine tests.

- [ ] **Step 6: Write the failure identifiers**

Create `Packages/Core/Sources/Updates/UpdateFailure.swift`:

```swift
import Foundation

/// What can go wrong on the way to a new version, as identifiers.
///
/// Shaped after `ProviderFailure` and for the same reason: the interface builds
/// the sentence, in the language the reader chose, and the diagnostic goes to
/// the log. A model that carried the sentence would have to be translated, and
/// `Packages/Core` holds no text meant to be read.
public struct UpdateFailure: Sendable, Hashable, Error {
    public enum Kind: Sendable, Hashable {
        /// GitHub could not be reached, or the download stopped.
        case network
        /// The newest release is missing the build it should carry.
        case malformedRelease
        /// What arrived is not what the release says it published.
        case checksumMismatch
        /// It arrived signed by somebody else.
        case signatureChanged
        /// The installed copy cannot be written where it sits.
        case notWritable
        /// The archive did not open, or held something other than the app.
        case unpackFailed
    }

    public let kind: Kind
    /// Detail for the log, not for a person: a status code, a file name, an
    /// exit status. Interface text is built from `kind`.
    public let diagnostic: String

    public init(kind: Kind, diagnostic: String = "") {
        self.kind = kind
        self.diagnostic = diagnostic
    }
}
```

- [ ] **Step 7: Run the whole suite**

```bash
make test
```
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Packages/Core/Package.swift Packages/Core/Sources/Updates Packages/Core/Tests/UpdatesTests
git commit -F - <<'MSG'
updates: a version that knows ten comes after nine

The first piece of the updater: a release version parsed from either
spelling — the tag's v0.1.42 and the bundle's 0.1.42 — and compared
numerically, component by component.

Text comparison is what this exists to avoid: it sorts 0.1.10 before 0.1.9,
so on the tenth release after a ninth the app would offer an update
backwards. Trailing zeros are dropped on the way in, because the bundle says
0.1 before any release has set a run number and a tag would say 0.1.0, and
those are one version.

Equality and hashing are written out rather than synthesised. The synthesised
pair would take the original text into account too, and 0.1 would then compare
equal to 0.1.0 while hashing differently — a Set holding both.

UpdateFailure comes along beside it, shaped after ProviderFailure: identifiers
for the interface to turn into sentences, and a diagnostic for the log.
MSG
```

---

### Task 3: Reading `SHA256SUMS.txt`

The release workflow writes it with `cd dist && shasum -a 256 ./*.dmg ./*.zip > SHA256SUMS.txt`, so every line reads `<64 hex>  ./Softcap-0.1.47.zip` — two spaces, and a `./` the lookup must not trip over.

**Files:**
- Create: `Packages/Core/Sources/Updates/Checksums.swift`
- Test: `Packages/Core/Tests/UpdatesTests/ChecksumsTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `Checksums(_ text: String)`
  - `Checksums.digest(for fileName: String) -> String?` — lowercase hex, looked up by last path component
  - `Checksums.count: Int`

- [ ] **Step 1: Write the failing test**

Create `Packages/Core/Tests/UpdatesTests/ChecksumsTests.swift`:

```swift
import Testing
import Foundation
@testable import Updates

@Suite struct ReadingTheChecksums {

    /// Exactly what `shasum -a 256 ./*.dmg ./*.zip` writes, which is what the
    /// release workflow runs.
    private let published = """
        3b1f8c2d4e5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c  ./Softcap-0.1.47.dmg
        9f8e7d6c5b4a39281706f5e4d3c2b1a09f8e7d6c5b4a39281706f5e4d3c2b1a0  ./Softcap.dmg
        1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef  ./Softcap-0.1.47.zip
        """

    @Test func aFileIsFoundByItsNameWithoutThePath() {
        let sums = Checksums(published)
        #expect(sums.digest(for: "Softcap-0.1.47.zip")
                == "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
    }

    @Test func everyPublishedFileIsThere() {
        #expect(Checksums(published).count == 3)
    }

    @Test func aFileNotPublishedHasNoDigest() {
        #expect(Checksums(published).digest(for: "Softcap-0.1.48.zip") == nil)
    }

    /// `shasum` marks a binary read with an asterisk on some systems, and the
    /// name must survive it.
    @Test func theBinaryMarkerIsNotPartOfTheName() {
        let sums = Checksums(
            "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef *Softcap-0.1.47.zip")
        #expect(sums.digest(for: "Softcap-0.1.47.zip") != nil)
    }

    @Test func digestsComeBackInOneCase() {
        let sums = Checksums(
            "ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890  ./x.zip")
        #expect(sums.digest(for: "x.zip")
                == "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890")
    }

    /// A line that is not a digest and a name is skipped rather than stored: a
    /// blank line, a heading somebody added, a truncated download. Storing it
    /// would mean a comparison that can never match, reported as a mismatch —
    /// which reads as tampering.
    @Test func whatIsNotAChecksumLineIsSkipped() {
        let sums = Checksums("""

            # SHA256
            not-a-digest  ./Softcap-0.1.47.zip
            1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef  ./real.zip
            deadbeef  ./tooshort.zip
            """)
        #expect(sums.count == 1)
        #expect(sums.digest(for: "real.zip") != nil)
    }

    @Test func anEmptyFileHoldsNothing() {
        #expect(Checksums("").count == 0)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd Packages/Core && swift test --filter ReadingTheChecksums
```
Expected: FAIL — `cannot find 'Checksums' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Packages/Core/Sources/Updates/Checksums.swift`:

```swift
import Foundation

/// The `SHA256SUMS.txt` a release publishes, read by file name.
///
/// The release workflow writes it with `shasum -a 256 ./*.dmg ./*.zip`, so a
/// line is a digest, a run of spaces, and a path beginning `./`. The path is
/// reduced to its last component: the lookup is for a published asset, and the
/// prefix is an artefact of the directory the command ran in.
public struct Checksums: Sendable {
    private let byName: [String: String]

    public init(_ text: String) {
        var found: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 2 else { continue }

            let digest = fields[0].lowercased()
            // A line that is not a checksum is skipped rather than stored.
            // Stored, it would be compared against and never match, and a
            // mismatch is reported to the reader as a download that was
            // tampered with.
            guard digest.count == 64, digest.allSatisfy(\.isHexDigit) else { continue }

            // `shasum` writes an asterisk before a name it read as binary.
            var name = String(fields[1])
            if name.hasPrefix("*") { name.removeFirst() }
            found[(name as NSString).lastPathComponent] = digest
        }
        byName = found
    }

    public var count: Int { byName.count }

    public func digest(for fileName: String) -> String? { byName[fileName] }
}
```

- [ ] **Step 4: Run the test**

```bash
cd Packages/Core && swift test --filter ReadingTheChecksums
```
Expected: PASS, seven tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/Core/Sources/Updates/Checksums.swift Packages/Core/Tests/UpdatesTests/ChecksumsTests.swift
git commit -F - <<'MSG'
updates: read the published checksums by file name

The release workflow writes SHA256SUMS.txt with shasum -a 256 ./*.dmg
./*.zip, so a line carries a ./ prefix from the directory the command ran
in. The lookup is by last path component, which drops it.

A line that is not a digest and a name is skipped rather than stored. Stored,
it would be compared against and could never match, and the interface reports
a mismatch as a download that was tampered with — an alarm raised by a blank
line.
MSG
```

---

### Task 4: When a check is due

**Files:**
- Create: `Packages/Core/Sources/Updates/UpdateSchedule.swift`
- Test: `Packages/Core/Tests/UpdatesTests/UpdateScheduleTests.swift`
- Test: `Packages/Core/Tests/StatusUITests/AskingWhetherToCheckRequiresAMomentTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `UpdateSchedule.interval: TimeInterval` — `86_400`
  - `UpdateSchedule.isDue(lastChecked: Date?, now: Date) -> Bool` — **`now` has no default**

- [ ] **Step 1: Write the failing tests**

Create `Packages/Core/Tests/UpdatesTests/UpdateScheduleTests.swift`:

```swift
import Testing
import Foundation
@testable import Updates

@Suite struct WhenACheckIsDue {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func hoursAgo(_ hours: Double) -> Date {
        now.addingTimeInterval(-hours * 3600)
    }

    @Test func nothingCheckedYetIsDue() {
        #expect(UpdateSchedule.isDue(lastChecked: nil, now: now))
    }

    @Test func acheckAnHourOldIsNotDue() {
        #expect(!UpdateSchedule.isDue(lastChecked: hoursAgo(1), now: now))
    }

    @Test func acheckADayOldIsDue() {
        #expect(UpdateSchedule.isDue(lastChecked: hoursAgo(24), now: now))
        #expect(UpdateSchedule.isDue(lastChecked: hoursAgo(48), now: now))
    }

    @Test func theBoundaryIsTheDayItself() {
        #expect(!UpdateSchedule.isDue(lastChecked: hoursAgo(23.9), now: now))
        #expect(UpdateSchedule.isDue(lastChecked: hoursAgo(24.1), now: now))
    }

    /// A clock corrected backwards — a machine that woke with the wrong time and
    /// then found a time server — leaves the last check in the future. Measured
    /// as an interval that is a negative age, which is never a day, and the app
    /// would stop checking until the clock caught up.
    @Test func acheckInTheFutureIsDueNow() {
        #expect(UpdateSchedule.isDue(lastChecked: now.addingTimeInterval(3600), now: now))
    }
}
```

Create `Packages/Core/Tests/StatusUITests/AskingWhetherToCheckRequiresAMomentTests.swift`:

```swift
import Testing
import Foundation

/// `now` is a required argument, and this is what keeps it one.
///
/// `ThresholdTracker.events(for:)` defaulted its moment to the system clock. A
/// test written before midnight set quiet hours of 1:00 to 2:00, passed all
/// evening, was committed green and pushed — and failed once one in the morning
/// arrived, with nothing changed. Green-then-red with no diff is worse than a
/// test that fails honestly, because there is nothing to read.
///
/// The compiler cannot help: adding a default back is source-compatible, every
/// call site keeps building, and the trap is reopened silently. So the source is
/// read instead.
@Suite struct AskingWhetherToCheckRequiresAMoment {

    @Test func theScheduleTakesTheMomentItIsAskedAbout() throws {
        let source = try String(contentsOf: Self.scheduleFile, encoding: .utf8)

        guard source.contains("isDue(") else {
            throw ScanIsLookingInTheWrongPlace(what: "isDue declaration", found: 0, least: 1)
        }

        // Any default at all, whichever way it is spelled.
        let defaulted = ["now: Date = ", "now: Date=", "now:Date="]
            .filter { source.contains($0) }

        #expect(defaulted.isEmpty, """
            UpdateSchedule defaults its moment to the clock again — the caller has to \
            say which moment it means, or a test written at one time of day fails at \
            another with nothing changed
            """)
    }

    private static var scheduleFile: URL {
        repositoryRoot
            .appendingPathComponent("Packages/Core/Sources/Updates/UpdateSchedule.swift")
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

```bash
cd Packages/Core && swift test --filter "WhenACheckIsDue|AskingWhetherToCheckRequiresAMoment"
```
Expected: FAIL — `cannot find 'UpdateSchedule' in scope`, and the guard throws `ScanIsLookingInTheWrongPlace` because the file is not there.

- [ ] **Step 3: Write the implementation**

Create `Packages/Core/Sources/Updates/UpdateSchedule.swift`:

```swift
import Foundation

/// How often the app looks for a new version, and whether it is time.
public enum UpdateSchedule {

    /// A day. Releases are cut per push to `main` and nobody needs them the
    /// hour they land; checking more often spends somebody's request budget on
    /// a question whose answer changes rarely.
    public static let interval: TimeInterval = 24 * 60 * 60

    /// Whether a check is due at `now`.
    ///
    /// `now` is required, and deliberately has no default. `ThresholdTracker`
    /// carried one and a test written before midnight failed at one in the
    /// morning with nothing changed — green, committed, pushed, then red. A
    /// caller that must name the moment cannot write that test.
    /// `AskingWhetherToCheckRequiresAMoment` keeps the default from coming back.
    public static func isDue(lastChecked: Date?, now: Date) -> Bool {
        guard let lastChecked else { return true }

        // A clock corrected backwards leaves the last check in the future, and
        // a negative age is never a day: the app would stop checking until the
        // clock caught up with itself.
        guard lastChecked <= now else { return true }

        return now.timeIntervalSince(lastChecked) >= interval
    }
}
```

- [ ] **Step 4: Run the tests**

```bash
cd Packages/Core && swift test --filter "WhenACheckIsDue|AskingWhetherToCheckRequiresAMoment"
```
Expected: PASS, seven tests.

- [ ] **Step 5: Mutation-test the guard**

Prove the guard would catch the default coming back:

```bash
python3 - <<'PY'
import pathlib
p = pathlib.Path("Packages/Core/Sources/Updates/UpdateSchedule.swift")
t = p.read_text()
p.write_text(t.replace("lastChecked: Date?, now: Date)", "lastChecked: Date?, now: Date = Date())"))
PY
cd Packages/Core && swift test --filter AskingWhetherToCheckRequiresAMoment
```
Expected: FAIL. Then put it back:

```bash
git checkout Packages/Core/Sources/Updates/UpdateSchedule.swift
cd Packages/Core && swift test --filter AskingWhetherToCheckRequiresAMoment
```
Expected: PASS.

Note: `git checkout` only restores it if the file is committed. If it is not yet, undo the replacement with the inverse `python3` call instead.

- [ ] **Step 6: Commit**

```bash
git add Packages/Core/Sources/Updates/UpdateSchedule.swift \
        Packages/Core/Tests/UpdatesTests/UpdateScheduleTests.swift \
        Packages/Core/Tests/StatusUITests/AskingWhetherToCheckRequiresAMomentTests.swift
git commit -F - <<'MSG'
updates: once a day, at a moment the caller names

The check runs at launch and a day apart after that. Releases are cut per
push and nobody needs one the hour it lands.

isDue takes `now` as a required argument. ThresholdTracker.events(for:)
defaulted its moment to the system clock, and a test written before midnight
against quiet hours of 1:00 to 2:00 passed all evening, was committed green,
and failed once one in the morning arrived with nothing changed. A caller
that must name the moment cannot write that test. The compiler cannot guard
it — adding the default back is source-compatible — so a test reads the
source, and it was checked by putting the default back and watching it fail.

A last check dated in the future counts as due. A clock corrected backwards
leaves one there, and a negative age is never a day: the app would go quiet
until the clock caught up.
MSG
```

---

### Task 5: Decoding the release feed

**Files:**
- Create: `Packages/Core/Sources/Updates/Release.swift`
- Create: `Packages/Core/Sources/Updates/ReleaseFeed.swift`
- Test: `Packages/Core/Tests/UpdatesTests/ReleaseFeedTests.swift`

**Interfaces:**
- Consumes: `ReleaseVersion`, `UpdateFailure` (Task 2)
- Produces:
  - `Release` with `version: ReleaseVersion`, `notes: String`, `archive: URL`, `archiveName: String`, `archiveSize: Int`, `checksums: URL`, `page: URL`
  - `ReleaseFeed.latestURL(owner:repository:) -> URL`
  - `ReleaseFeed.releasePage(owner:repository:) -> URL`
  - `ReleaseFeed.decode(_ data: Data) throws -> Release`
  - `ReleaseFeed.update(from data: Data, running: ReleaseVersion) throws -> Release?` — `nil` when nothing newer

- [ ] **Step 1: Write the failing test**

Create `Packages/Core/Tests/UpdatesTests/ReleaseFeedTests.swift`:

```swift
import Testing
import Foundation
@testable import Updates

@Suite struct DecodingTheReleaseFeed {

    /// Trimmed from a real response: the fields this reads, and two it ignores,
    /// so that a decoder written to refuse unknown keys is caught here.
    private func payload(
        tag: String = "v0.1.47",
        draft: Bool = false,
        prerelease: Bool = false,
        assets: String = """
            {"name": "Softcap-0.1.47.dmg", "browser_download_url": "https://github.com/milushov/softcap/releases/download/v0.1.47/Softcap-0.1.47.dmg", "size": 4100000},
            {"name": "Softcap-0.1.47.zip", "browser_download_url": "https://github.com/milushov/softcap/releases/download/v0.1.47/Softcap-0.1.47.zip", "size": 3900000},
            {"name": "SHA256SUMS.txt", "browser_download_url": "https://github.com/milushov/softcap/releases/download/v0.1.47/SHA256SUMS.txt", "size": 300}
            """
    ) -> Data {
        Data("""
            {
              "id": 12345,
              "tag_name": "\(tag)",
              "name": "0.1.47",
              "draft": \(draft),
              "prerelease": \(prerelease),
              "html_url": "https://github.com/milushov/softcap/releases/tag/\(tag)",
              "body": "Built from `abc1234`.\\n\\n- something changed",
              "assets": [\(assets)]
            }
            """.utf8)
    }

    private func kind(of error: any Error) -> UpdateFailure.Kind? {
        (error as? UpdateFailure)?.kind
    }

    @Test func areleaseCarriesItsVersionNotesAndArchive() throws {
        let release = try ReleaseFeed.decode(payload())
        #expect(release.version == ReleaseVersion("0.1.47"))
        #expect(release.archiveName == "Softcap-0.1.47.zip")
        #expect(release.archiveSize == 3_900_000)
        #expect(release.notes.contains("something changed"))
        #expect(release.checksums.lastPathComponent == "SHA256SUMS.txt")
    }

    /// The zip, not the disk image. A disk image has to be mounted and the app
    /// copied out of it; the zip is what `ditto` opens in one step, and it is
    /// published for exactly this.
    @Test func theArchiveIsTheZipAndNotTheImage() throws {
        #expect(try ReleaseFeed.decode(payload()).archive.pathExtension == "zip")
    }

    @Test func areleaseWithNoBuildIsMalformed() {
        let assets = """
            {"name": "SHA256SUMS.txt", "browser_download_url": "https://github.com/x/y/releases/download/v1/SHA256SUMS.txt", "size": 30}
            """
        #expect(throws: UpdateFailure.self) {
            try ReleaseFeed.decode(payload(assets: assets))
        }
        let error = #expect(throws: UpdateFailure.self) {
            try ReleaseFeed.decode(payload(assets: assets))
        }
        #expect(error?.kind == .malformedRelease)
    }

    /// The sums are how the download is checked. A release without them is not
    /// one this app can install, and installing it unchecked is the wrong way
    /// to be forgiving.
    @Test func areleaseWithNoChecksumsIsMalformed() {
        let assets = """
            {"name": "Softcap-0.1.47.zip", "browser_download_url": "https://github.com/x/y/releases/download/v1/Softcap-0.1.47.zip", "size": 39}
            """
        let error = #expect(throws: UpdateFailure.self) {
            try ReleaseFeed.decode(payload(assets: assets))
        }
        #expect(error?.kind == .malformedRelease)
    }

    @Test func atagThatIsNotAVersionIsMalformed() {
        let error = #expect(throws: UpdateFailure.self) {
            try ReleaseFeed.decode(payload(tag: "nightly"))
        }
        #expect(error?.kind == .malformedRelease)
    }

    /// `/releases/latest` excludes both already. Refusing them here as well
    /// keeps the rule in the code rather than only in the shape of a URL,
    /// where the next person to reach for `/releases` would not find it.
    @Test func adraftIsNotARelease() {
        #expect(throws: UpdateFailure.self) { try ReleaseFeed.decode(payload(draft: true)) }
    }

    @Test func aprereleaseIsNotARelease() {
        #expect(throws: UpdateFailure.self) { try ReleaseFeed.decode(payload(prerelease: true)) }
    }

    @Test func somethingThatIsNotJsonIsMalformed() {
        let error = #expect(throws: UpdateFailure.self) {
            try ReleaseFeed.decode(Data("<html>rate limited</html>".utf8))
        }
        #expect(error?.kind == .malformedRelease)
    }

    // MARK: - what counts as an update

    @Test func anewerReleaseIsAnUpdate() throws {
        let running = try #require(ReleaseVersion("0.1.42"))
        #expect(try ReleaseFeed.update(from: payload(), running: running) != nil)
    }

    @Test func thesameVersionIsNotAnUpdate() throws {
        let running = try #require(ReleaseVersion("0.1.47"))
        #expect(try ReleaseFeed.update(from: payload(), running: running) == nil)
    }

    /// A locally built app can be ahead of the newest release. Offering to move
    /// it backwards is not an update.
    @Test func anolderReleaseIsNotAnUpdate() throws {
        let running = try #require(ReleaseVersion("0.2.0"))
        #expect(try ReleaseFeed.update(from: payload(), running: running) == nil)
    }

    @Test func theFeedUrlNamesTheRepository() {
        #expect(ReleaseFeed.latestURL(owner: "milushov", repository: "softcap").absoluteString
                == "https://api.github.com/repos/milushov/softcap/releases/latest")
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd Packages/Core && swift test --filter DecodingTheReleaseFeed
```
Expected: FAIL — `cannot find 'ReleaseFeed' in scope`.

- [ ] **Step 3: Write `Release`**

Create `Packages/Core/Sources/Updates/Release.swift`:

```swift
import Foundation

/// A published release, reduced to what installing one needs.
public struct Release: Sendable, Hashable, Identifiable {
    public var id: String { version.description }

    public let version: ReleaseVersion
    /// The release body, as the person who cut it wrote it. Markdown, and text
    /// that arrived over the network rather than a label written into a model —
    /// which is why it does not break the rule about strings in the core.
    public let notes: String

    public let archive: URL
    public let archiveName: String
    public let archiveSize: Int
    public let checksums: URL

    /// Where to send somebody when the updater cannot finish.
    public let page: URL

    public init(
        version: ReleaseVersion, notes: String, archive: URL, archiveName: String,
        archiveSize: Int, checksums: URL, page: URL
    ) {
        self.version = version
        self.notes = notes
        self.archive = archive
        self.archiveName = archiveName
        self.archiveSize = archiveSize
        self.checksums = checksums
        self.page = page
    }
}
```

- [ ] **Step 4: Write `ReleaseFeed`**

Create `Packages/Core/Sources/Updates/ReleaseFeed.swift`:

```swift
import Foundation

/// The newest published release, read from GitHub.
public enum ReleaseFeed {

    public static func latestURL(owner: String, repository: String) -> URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest")!
    }

    /// Where a person is sent when the updater cannot finish by itself.
    public static func releasePage(owner: String, repository: String) -> URL {
        URL(string: "https://github.com/\(owner)/\(repository)/releases/latest")!
    }

    /// The newest release, or `nil` when it is not newer than what is running.
    ///
    /// A release older than the running app is not an update. A locally built
    /// app reports the marketing version alone and can be ahead of everything
    /// published; offering to move it backwards is not an offer worth making.
    public static func update(from data: Data, running: ReleaseVersion) throws -> Release? {
        let release = try decode(data)
        guard release.version > running else { return nil }
        return release
    }

    public static func decode(_ data: Data) throws -> Release {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            // A rate-limited response is HTML, and an outage is a status page.
            // Neither is a release, and neither is worth a different sentence.
            throw UpdateFailure(kind: .malformedRelease,
                                diagnostic: "response did not decode: \(type(of: error))")
        }

        guard !payload.draft, !payload.prerelease else {
            throw UpdateFailure(kind: .malformedRelease, diagnostic: "draft or prerelease")
        }

        guard let version = ReleaseVersion(payload.tagName) else {
            throw UpdateFailure(kind: .malformedRelease,
                                diagnostic: "tag is not a version: \(payload.tagName)")
        }

        // The zip, not the disk image: an image has to be mounted and the app
        // copied out of it, and the zip is published for exactly this.
        guard let archive = payload.assets.first(where: {
            $0.name.hasPrefix("Softcap-") && $0.name.hasSuffix(".zip")
        }) else {
            throw UpdateFailure(kind: .malformedRelease, diagnostic: "no zip asset")
        }

        // Without the sums there is nothing to check the download against, and
        // installing it unchecked is the wrong way to be forgiving.
        guard let sums = payload.assets.first(where: { $0.name == "SHA256SUMS.txt" }) else {
            throw UpdateFailure(kind: .malformedRelease, diagnostic: "no checksums asset")
        }

        return Release(
            version: version,
            notes: payload.body ?? "",
            archive: archive.browserDownloadURL,
            archiveName: archive.name,
            archiveSize: archive.size,
            checksums: sums.browserDownloadURL,
            page: payload.htmlURL
        )
    }

    // MARK: -

    /// The fields this reads. Unknown keys are ignored, which is what a
    /// synthesised `Decodable` does and what keeps a new field on GitHub's side
    /// from becoming an app that cannot find an update.
    private struct Payload: Decodable {
        let tagName: String
        let body: String?
        let draft: Bool
        let prerelease: Bool
        let htmlURL: URL
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body, draft, prerelease
            case htmlURL = "html_url"
            case assets
        }

        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL
            let size: Int

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
                case size
            }
        }
    }
}
```

- [ ] **Step 5: Run the test**

```bash
cd Packages/Core && swift test --filter DecodingTheReleaseFeed
```
Expected: PASS, twelve tests.

- [ ] **Step 6: Run the whole suite**

```bash
make test
```

Expected: **`NothingElseLeavesYourMac.everyHostIsOneWeNamed` now FAILS**, naming `api.github.com` and `github.com` in `ReleaseFeed.swift`. That is the guard doing its job; Task 6 answers it. Leave it failing and go on — do **not** commit with a red suite.

- [ ] **Step 7: Do not commit yet**

This task's commit is folded into Task 6, because the host list and the landing sentence are the same decision as adding the URL. Committing a red suite in between would be worse than one larger commit.

---

### Task 6: The second door, the named hosts, and the promise on the page

Downloading a build with a progress bar needs more than `HTTPClient.get`. `URLSession.download(from:)` takes a bare URL and would slip past `oneTypeBuildsEveryRequest` without ever naming a `URLRequest` — passing the guard on a technicality, which is worse than failing it. So a second protocol is declared and implemented in the same file, and it builds a real request.

**Files:**
- Modify: `Packages/Core/Sources/ClaudeProvider/HTTPClient.swift`
- Modify: `Packages/Core/Tests/StatusUITests/NothingElseLeavesYourMacTests.swift:29-35`
- Modify: `site/index.html:609-610`

**Interfaces:**
- Consumes: `HTTPClient` (existing), `ProviderFailure` (existing)
- Produces:
  - `FileDownloader.download(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL` — throws `ProviderFailure`, returns a file in the temporary directory that the **caller owns and must remove**
  - `URLSessionFileDownloader()`

- [ ] **Step 1: Add the hosts to the guard**

In `Packages/Core/Tests/StatusUITests/NothingElseLeavesYourMacTests.swift`, the `named` dictionary reads:

```swift
        let named: [String: String] = [
            "api.anthropic.com":   "the Claude usage endpoint — the one live request",
            "platform.claude.com": "OAuth authorize and token, and the manual redirect",
            "claude.com":          "where the sign-in flow sends the browser",
            "api.openai.com":      "not fetched: the namespace of a claim inside a Codex token",
            "localhost":           "the loopback the PKCE redirect comes back to",
        ]
```

Add two entries:

```swift
            "api.github.com":      "the release feed, once a day, and only when asked to",
            "github.com":          "the release page, and the build a release publishes",
```

- [ ] **Step 2: Rewrite the promise on the page**

`site/index.html:609-610` reads:

```html
        <p>Credentials stay in the keychain, never copied into preferences or logs. No telemetry;
           nothing else leaves your Mac.</p>
```

Replace it with:

```html
        <p>Credentials stay in the keychain, never copied into preferences or logs. No telemetry.
           The only other request is a daily check for a new version, and it can be switched off.</p>
```

`thePageStillMakesThePromise` requires the page to say "Credentials stay in the keychain" and "No telemetry"; both survive.

- [ ] **Step 3: Write the failing test for the downloader**

Add to `Packages/Core/Tests/ClaudeProviderTests/` a new file `FileDownloaderTests.swift`:

```swift
import Testing
import Foundation
@testable import ClaudeProvider

/// The downloader is not exercised against the network — no test in this
/// project reaches it. What is checked is the part that has been wrong before:
/// the file it hands back is the caller's to keep, and it is not the one the
/// system deletes the moment the delegate returns.
@Suite struct DownloadingAFile {

    @Test func afileIsServedFromDiskAndKept() async throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("softcap-download-\(UUID().uuidString).bin")
        try Data(repeating: 7, count: 64 * 1024).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        var seen: [Double] = []
        let downloader = URLSessionFileDownloader()
        let result = try await downloader.download(source) { seen.append($0) }
        defer { try? FileManager.default.removeItem(at: result) }

        #expect(FileManager.default.fileExists(atPath: result.path))
        #expect(try Data(contentsOf: result).count == 64 * 1024)
        #expect(result != source, "the caller was handed the file it was asked to copy")
        #expect(seen.last == 1, "progress never reached the end")
    }

    @Test func afileThatIsNotThereIsANetworkFailure() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("softcap-not-here-\(UUID().uuidString).bin")
        let downloader = URLSessionFileDownloader()
        await #expect(throws: ProviderFailure.self) {
            _ = try await downloader.download(missing) { _ in }
        }
    }
}
```

`URLSession` serves `file:` URLs, so this exercises the real delegate path without a server.

- [ ] **Step 4: Run it and watch it fail**

```bash
cd Packages/Core && swift test --filter DownloadingAFile
```
Expected: FAIL — `cannot find 'URLSessionFileDownloader' in scope`.

- [ ] **Step 5: Implement the downloader**

Append to `Packages/Core/Sources/ClaudeProvider/HTTPClient.swift`:

```swift
/// Fetching a file, with progress, to a place the caller keeps.
///
/// Separate from `HTTPClient` because no provider needs it, and declared in
/// this file because this is the one file in the project that builds a
/// `URLRequest` — a rule `NothingElseLeavesYourMac` holds, and the reason the
/// list of hosts beside it is worth reading.
///
/// `URLSession.download(from:)` would have been shorter and takes a bare URL:
/// it would have passed that check without ever naming a request, which is
/// worse than failing it.
public protocol FileDownloader: Sendable {
    /// Downloads `url` and hands back a file in the temporary directory.
    /// The caller owns it and is responsible for removing it.
    func download(
        _ url: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL
}

public struct URLSessionFileDownloader: FileDownloader {
    public init() {}

    public func download(
        _ url: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        // A minute to start, not to finish: a build is several megabytes and
        // `timeoutInterval` measures the gap between packets, not the whole.
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "GET"

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadDelegate(progress: progress, continuation: continuation)
            let session = URLSession(
                configuration: .default, delegate: delegate, delegateQueue: nil)
            session.downloadTask(with: request).resume()
            // A session holds its delegate strongly until it is invalidated.
            // This lets the task finish and then lets both go.
            session.finishTasksAndInvalidate()
        }
    }
}

/// The delegate exists for one reason: `didWriteData` is the only place a
/// download reports how far it has got, and the async API does not surface it.
///
/// `@unchecked Sendable` with a lock, because the callbacks arrive on the
/// session's own queue and the continuation must be resumed exactly once —
/// `didCompleteWithError` also fires after a successful download.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, any Error>?

    init(
        progress: @escaping @Sendable (Double) -> Void,
        continuation: CheckedContinuation<URL, any Error>
    ) {
        self.progress = progress
        self.continuation = continuation
    }

    private func finish(_ result: Result<URL, any Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The system deletes `location` as soon as this returns, so the file is
        // moved before anything else is allowed to happen to it.
        let kept = FileManager.default.temporaryDirectory
            .appendingPathComponent("softcap-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            progress(1)
            finish(.success(kept))
        } catch {
            finish(.failure(ProviderFailure(
                kind: .network, diagnostic: "the download could not be kept")))
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
    ) {
        // Success is reported by `didFinishDownloadingTo`, which has already
        // resumed the continuation; `finish` ignores a second call.
        guard let error else { return }
        let code = (error as? URLError)?.errorCode
        finish(.failure(ProviderFailure(
            kind: .network,
            diagnostic: "download failed: \(code.map { "URLError \($0)" } ?? "\(type(of: error))")"
        )))
    }
}
```

- [ ] **Step 6: Run the tests**

```bash
cd Packages/Core && swift test --filter "DownloadingAFile|NothingElseLeavesYourMac"
```
Expected: PASS.

- [ ] **Step 7: Run the whole suite**

```bash
make test
```
Expected: PASS — the failure Task 5 left is answered.

- [ ] **Step 8: Commit**

```bash
git add Packages/Core/Sources/Updates/Release.swift \
        Packages/Core/Sources/Updates/ReleaseFeed.swift \
        Packages/Core/Tests/UpdatesTests/ReleaseFeedTests.swift \
        Packages/Core/Sources/ClaudeProvider/HTTPClient.swift \
        Packages/Core/Tests/ClaudeProviderTests/FileDownloaderTests.swift \
        Packages/Core/Tests/StatusUITests/NothingElseLeavesYourMacTests.swift \
        site/index.html
git commit -F - <<'MSG'
updates: the release feed, a second door, and a sentence that had to change

The newest release is read from api.github.com, reduced to what installing
one needs: the version, the notes, the zip, and the checksums beside it. A
release missing either file is refused rather than half-installed, and a
release older than what is running is not an update — a locally built app
reports the marketing version alone and can be ahead of everything published.

Downloading a build with a progress bar needs more than HTTPClient.get.
URLSession.download(from:) takes a bare URL and would have passed the check
that says one file builds every URLRequest without ever naming one — passing
a guard on a technicality is worse than failing it. So FileDownloader is
declared in that same file and builds a real request, and the check still
means what it says.

The landing promised "No telemetry; nothing else leaves your Mac". A version
check is a request that leaves. It carries nothing about the reader, but
GitHub sees an address, and the sentence as written said that does not
happen. It now says what does, and that it can be switched off. The host
check is what forced the question, which is what it is for.
MSG
```

---

### Task 7: Installing

**Files:**
- Create: `Packages/Core/Sources/Updates/UpdateInstaller.swift`
- Test: `Packages/Core/Tests/UpdatesTests/UpdateInstallerTests.swift`

**Interfaces:**
- Consumes: `Release`, `Checksums`, `UpdateFailure`, `FileDownloader`, `HTTPClient`
- Produces:
  - `UpdateInstaller(downloader:http:)`
  - `UpdateInstaller.Phase`: `.downloading(Double)`, `.verifying`, `.installing`
  - `UpdateInstaller.install(_ release: Release, replacing bundle: URL, progress:) async throws`
  - `UpdateInstaller.restart(_ bundle: URL)` — static, separate so a test can install without relaunching anything
  - `String.singleQuotedForShell`

- [ ] **Step 1: Write the failing tests**

Create `Packages/Core/Tests/UpdatesTests/UpdateInstallerTests.swift`:

```swift
import Testing
import Foundation
@testable import Updates
@testable import ClaudeProvider

@Suite struct InstallingAnUpdate {

    // MARK: - the world the installer is given

    /// Hands back a file already on disk, so the whole install runs without a
    /// network and without a server.
    private struct FileOnDisk: FileDownloader {
        let file: URL
        func download(
            _ url: URL, progress: @escaping @Sendable (Double) -> Void
        ) async throws -> URL {
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("softcap-test-\(UUID().uuidString)")
            try FileManager.default.copyItem(at: file, to: copy)
            progress(1)
            return copy
        }
    }

    /// Answers every GET with one body: the only GET the installer makes is for
    /// the checksums.
    private struct OneAnswer: HTTPClient {
        let body: String
        func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
            (Data(body.utf8), 200)
        }
        func post(
            _ url: URL, headers: [String: String], body: Data
        ) async throws -> (Data, Int) {
            (Data(), 405)
        }
    }

    // MARK: - building an app bundle and zipping it, as the release does

    private func makeBundle(
        in directory: URL, version: String, identifier: String = "app.softcap.Softcap"
    ) throws -> URL {
        let app = directory.appendingPathComponent("Softcap.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(
            at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
            <key>CFBundleIdentifier</key><string>\(identifier)</string>
            <key>CFBundleShortVersionString</key><string>\(version)</string>
            <key>CFBundleExecutable</key><string>Softcap</string>
            </dict></plist>
            """
        try plist.write(
            to: contents.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        try Data("#!/bin/sh\n".utf8)
            .write(to: contents.appendingPathComponent("MacOS/Softcap"))
        return app
    }

    private func zip(_ app: URL, to archive: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", app.path, archive.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "the fixture archive was not built")
    }

    private func sha256(of file: URL) throws -> String {
        try Checksums.digest(ofFileAt: file)
    }

    private func scratch() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("softcap-install-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func release(
        version: String, archiveName: String = "Softcap-0.1.47.zip"
    ) throws -> Release {
        Release(
            version: try #require(ReleaseVersion(version)),
            notes: "",
            archive: URL(string: "https://github.com/milushov/softcap/releases/download/v\(version)/\(archiveName)")!,
            archiveName: archiveName,
            archiveSize: 0,
            checksums: URL(string: "https://github.com/milushov/softcap/releases/download/v\(version)/SHA256SUMS.txt")!,
            page: URL(string: "https://github.com/milushov/softcap/releases/latest")!
        )
    }

    // MARK: - the guard this suite exists for

    /// Nothing is installed that did not match what the release published.
    ///
    /// This is the whole security of the thing. The download is not quarantined
    /// — `URLSession` does not mark a file the way a browser does — so nothing
    /// downstream will ask a second time.
    @Test func adownloadThatDoesNotMatchIsNotInstalled() async throws {
        let scratch = try scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let source = try makeBundle(in: scratch, version: "0.1.47")
        let archive = scratch.appendingPathComponent("Softcap-0.1.47.zip")
        try zip(source, to: archive)

        let installed = try makeBundle(
            in: try { let d = scratch.appendingPathComponent("Applications")
                      try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
                      return d }(),
            version: "0.1.42")
        let before = try Data(contentsOf: installed
            .appendingPathComponent("Contents/Info.plist"))

        let wrong = String(repeating: "a", count: 64)
        let installer = UpdateInstaller(
            downloader: FileOnDisk(file: archive),
            http: OneAnswer(body: "\(wrong)  ./Softcap-0.1.47.zip")
        )

        let error = await #expect(throws: UpdateFailure.self) {
            try await installer.install(
                try release(version: "0.1.47"), replacing: installed) { _ in }
        }
        #expect(error?.kind == .checksumMismatch)

        let after = try Data(contentsOf: installed
            .appendingPathComponent("Contents/Info.plist"))
        #expect(after == before, "the installed app was touched by a download that did not match")
    }

    /// A release with no line for its own archive is the same refusal: there is
    /// nothing to compare against, and installing unchecked is not the
    /// forgiving thing to do.
    @Test func achecksumFileThatDoesNotMentionTheArchiveIsARefusal() async throws {
        let scratch = try scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let source = try makeBundle(in: scratch, version: "0.1.47")
        let archive = scratch.appendingPathComponent("Softcap-0.1.47.zip")
        try zip(source, to: archive)
        let installed = try makeBundle(in: scratch, version: "0.1.42")

        let installer = UpdateInstaller(
            downloader: FileOnDisk(file: archive),
            http: OneAnswer(body: "\(String(repeating: "b", count: 64))  ./something-else.zip")
        )

        let error = await #expect(throws: UpdateFailure.self) {
            try await installer.install(
                try release(version: "0.1.47"), replacing: installed) { _ in }
        }
        #expect(error?.kind == .checksumMismatch)
    }

    // MARK: - the happy path

    @Test func amatchingDownloadReplacesTheApp() async throws {
        let scratch = try scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let staging = scratch.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let source = try makeBundle(in: staging, version: "0.1.47")
        let archive = scratch.appendingPathComponent("Softcap-0.1.47.zip")
        try zip(source, to: archive)

        let applications = scratch.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        let installed = try makeBundle(in: applications, version: "0.1.42")

        let installer = UpdateInstaller(
            downloader: FileOnDisk(file: archive),
            http: OneAnswer(body: "\(try sha256(of: archive))  ./Softcap-0.1.47.zip")
        )

        var phases: [String] = []
        try await installer.install(
            try release(version: "0.1.47"), replacing: installed
        ) { phase in
            switch phase {
            case .downloading: if phases.last != "downloading" { phases.append("downloading") }
            case .verifying:   phases.append("verifying")
            case .installing:  phases.append("installing")
            }
        }

        let plist = try String(
            contentsOf: installed.appendingPathComponent("Contents/Info.plist"), encoding: .utf8)
        #expect(plist.contains("0.1.47"), "the app in place is still the old one")
        #expect(phases == ["downloading", "verifying", "installing"])
    }

    /// A zip that opens into something other than the app is not installed,
    /// however well its checksum matches — a matching checksum only says the
    /// bytes are the ones published, not that they are the right ones.
    @Test func anarchiveHoldingSomethingElseIsRefused() async throws {
        let scratch = try scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let staging = scratch.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let stranger = try makeBundle(
            in: staging, version: "0.1.47", identifier: "com.example.Something")
        let archive = scratch.appendingPathComponent("Softcap-0.1.47.zip")
        try zip(stranger, to: archive)

        let installed = try makeBundle(in: scratch, version: "0.1.42")

        let installer = UpdateInstaller(
            downloader: FileOnDisk(file: archive),
            http: OneAnswer(body: "\(try sha256(of: archive))  ./Softcap-0.1.47.zip")
        )

        let error = await #expect(throws: UpdateFailure.self) {
            try await installer.install(
                try release(version: "0.1.47"), replacing: installed) { _ in }
        }
        #expect(error?.kind == .unpackFailed)
    }

    /// The version in the archive has to be the version the release claimed, or
    /// the app would report a number nobody published.
    @Test func anarchiveHoldingAdifferentVersionIsRefused() async throws {
        let scratch = try scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let staging = scratch.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let source = try makeBundle(in: staging, version: "0.1.99")
        let archive = scratch.appendingPathComponent("Softcap-0.1.47.zip")
        try zip(source, to: archive)

        let installed = try makeBundle(in: scratch, version: "0.1.42")

        let installer = UpdateInstaller(
            downloader: FileOnDisk(file: archive),
            http: OneAnswer(body: "\(try sha256(of: archive))  ./Softcap-0.1.47.zip")
        )

        let error = await #expect(throws: UpdateFailure.self) {
            try await installer.install(
                try release(version: "0.1.47"), replacing: installed) { _ in }
        }
        #expect(error?.kind == .unpackFailed)
    }
}

/// The relaunch runs through a shell, and a path is not a shell word.
@Suite struct PathsSurviveTheShell {

    @Test func aspaceDoesNotEndTheArgument() {
        #expect("/Applications/My Apps/Softcap.app".singleQuotedForShell
                == "'/Applications/My Apps/Softcap.app'")
    }

    /// The one character single quotes cannot carry. A folder named after
    /// somebody is enough to meet it.
    @Test func anapostropheIsEscaped() {
        #expect("/Users/o'brien/Softcap.app".singleQuotedForShell
                == "'/Users/o'\\''brien/Softcap.app'")
    }

    @Test func nothingElseIsTouched() {
        #expect("/Applications/Softcap.app".singleQuotedForShell
                == "'/Applications/Softcap.app'")
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

```bash
cd Packages/Core && swift test --filter "InstallingAnUpdate|PathsSurviveTheShell"
```
Expected: FAIL — `cannot find 'UpdateInstaller' in scope`.

- [ ] **Step 3: Add the digest helper to `Checksums`**

Append to `Packages/Core/Sources/Updates/Checksums.swift`:

```swift
import CryptoKit

extension Checksums {
    /// SHA-256 of a file, as lowercase hex — the spelling `shasum -a 256`
    /// writes, so the two can be compared as text.
    ///
    /// Read in chunks rather than into memory at once: a build is several
    /// megabytes today and there is no reason for it to be resident.
    public static func digest(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 4: Write the installer**

Create `Packages/Core/Sources/Updates/UpdateInstaller.swift`:

```swift
import Foundation
import Security
import ProviderKit
import ClaudeProvider

/// Downloading a release and putting it where the running app is.
///
/// Each step is refused rather than worked around. What is installed is what
/// the release published, is the app, and is the version it said it was —
/// because nothing downstream will ask again: `URLSession` does not mark a file
/// with `com.apple.quarantine` the way a browser does, so Gatekeeper never sees
/// it. That is the feature — an update that opens without the dialog an
/// ad-hoc signed build otherwise gets — and it is also why these checks are the
/// only ones there are.
public struct UpdateInstaller: Sendable {

    public enum Phase: Sendable, Equatable {
        case downloading(Double)
        case verifying
        case installing
    }

    private let downloader: any FileDownloader
    private let http: any HTTPClient

    public init(downloader: any FileDownloader, http: any HTTPClient) {
        self.downloader = downloader
        self.http = http
    }

    /// Replaces the bundle at `bundle` with the build `release` publishes.
    ///
    /// Does not restart: `restart(_:)` is separate so that a test can install
    /// without relaunching anything.
    public func install(
        _ release: Release,
        replacing bundle: URL,
        progress: @escaping @Sendable (Phase) -> Void
    ) async throws {
        let work = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: work) }

        // 1 — download
        progress(.downloading(0))
        let archive: URL
        do {
            archive = try await downloader.download(release.archive) {
                progress(.downloading($0))
            }
        } catch {
            throw Self.networkFailure(error)
        }
        defer { try? FileManager.default.removeItem(at: archive) }

        // 2 — verify
        progress(.verifying)
        try await verify(archive, of: release)

        // 3 — unpack, and check what came out
        let unpacked = try unpack(archive, into: work)
        try check(unpacked, isSoftcapAt: release.version)
        try checkSigningIdentity(of: unpacked, matches: bundle)

        // 4 — replace
        progress(.installing)
        try replace(bundle, with: unpacked)
    }

    // MARK: - verifying

    private func verify(_ archive: URL, of release: Release) async throws {
        let published: Checksums
        do {
            let (data, status) = try await http.get(release.checksums, headers: [:])
            guard status == 200, let text = String(data: data, encoding: .utf8) else {
                throw UpdateFailure(kind: .checksumMismatch,
                                    diagnostic: "checksums came back \(status)")
            }
            published = Checksums(text)
        } catch let failure as UpdateFailure {
            throw failure
        } catch {
            throw Self.networkFailure(error)
        }

        guard let expected = published.digest(for: release.archiveName) else {
            throw UpdateFailure(kind: .checksumMismatch,
                                diagnostic: "no line for \(release.archiveName)")
        }

        let actual = try Checksums.digest(ofFileAt: archive)
        guard actual == expected else {
            throw UpdateFailure(kind: .checksumMismatch,
                                diagnostic: "got \(actual.prefix(12)), expected \(expected.prefix(12))")
        }
    }

    // MARK: - unpacking

    /// `ditto`, not `unzip`: it is the only one that keeps a bundle's symlinks
    /// and its signature intact, and it is what the release workflow used to
    /// build the archive.
    private func unpack(_ archive: URL, into directory: URL) throws -> URL {
        let out = directory.appendingPathComponent("unpacked")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, out.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw UpdateFailure(kind: .unpackFailed, diagnostic: "ditto would not run")
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateFailure(kind: .unpackFailed,
                                diagnostic: "ditto exited \(process.terminationStatus)")
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: out, includingPropertiesForKeys: nil)
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateFailure(kind: .unpackFailed, diagnostic: "no bundle in the archive")
        }
        return app
    }

    /// A matching checksum says the bytes are the ones published. It does not
    /// say they are the right ones — a release that shipped the wrong artefact
    /// would checksum perfectly.
    private func check(_ bundle: URL, isSoftcapAt version: ReleaseVersion) throws {
        let plist = bundle.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist) as? [String: Any] else {
            throw UpdateFailure(kind: .unpackFailed, diagnostic: "no Info.plist")
        }
        guard info["CFBundleIdentifier"] as? String == Self.bundleIdentifier else {
            throw UpdateFailure(kind: .unpackFailed, diagnostic: "another app's bundle")
        }
        guard let text = info["CFBundleShortVersionString"] as? String,
              let found = ReleaseVersion(text), found == version else {
            throw UpdateFailure(
                kind: .unpackFailed,
                diagnostic: "the archive holds \(info["CFBundleShortVersionString"] ?? "nothing")"
            )
        }
    }

    /// The check that would notice a swapped bundle — and only for a build
    /// signed with a Developer ID.
    ///
    /// An ad-hoc signature is regenerated on every build and identifies nobody,
    /// so there is nothing to compare and the step passes. That is stated here
    /// rather than dressed up: an interface that implied a check nobody
    /// performed would be worse than no check at all.
    private func checkSigningIdentity(of new: URL, matches current: URL) throws {
        guard let running = Self.teamIdentifier(of: current) else { return }
        let arriving = Self.teamIdentifier(of: new)
        guard arriving == running else {
            throw UpdateFailure(kind: .signatureChanged,
                                diagnostic: "signed by \(arriving ?? "nobody")")
        }
    }

    private static func teamIdentifier(of bundle: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess,
              let code else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &information) == errSecSuccess,
              let dictionary = information as? [String: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }

    // MARK: - replacing

    /// Atomic on APFS: the old bundle is kept until the new one is in place,
    /// and a failure leaves what was there.
    ///
    /// The copy is staged beside the installed app rather than left in the
    /// temporary directory, because `replaceItemAt` is only atomic within a
    /// volume — and a bundle half-moved across one is where an app that will
    /// not launch comes from.
    private func replace(_ current: URL, with new: URL) throws {
        let fileManager = FileManager.default
        let staged = current.deletingLastPathComponent()
            .appendingPathComponent(".\(current.lastPathComponent).incoming")

        try? fileManager.removeItem(at: staged)
        do {
            try fileManager.copyItem(at: new, to: staged)
        } catch {
            throw UpdateFailure(kind: .notWritable,
                                diagnostic: "could not write beside the installed app")
        }

        do {
            _ = try fileManager.replaceItemAt(current, withItemAt: staged)
        } catch {
            try? fileManager.removeItem(at: staged)
            throw UpdateFailure(kind: .notWritable, diagnostic: "could not replace the app")
        }
    }

    // MARK: - restarting

    /// Quits and comes back.
    ///
    /// The wait is not decoration: `open` on a bundle whose app is still
    /// running activates the copy already in memory rather than launching the
    /// new one, and the update would appear not to have happened until the next
    /// launch.
    public static func restart(_ bundle: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; "
                + "/usr/bin/open \(bundle.path.singleQuotedForShell)",
        ]
        try? process.run()
    }

    // MARK: -

    public static let bundleIdentifier = "app.softcap.Softcap"

    private func scratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("softcap-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// A provider's failure, said in this module's words.
    private static func networkFailure(_ error: any Error) -> UpdateFailure {
        UpdateFailure(kind: .network,
                      diagnostic: (error as? ProviderFailure)?.diagnostic ?? "\(type(of: error))")
    }
}

extension String {
    /// A path is not a shell word: a space ends the argument and a quote ends
    /// the string. Single quotes carry everything except a single quote, which
    /// is closed, escaped, and reopened.
    public var singleQuotedForShell: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
```

- [ ] **Step 5: Run the tests**

```bash
cd Packages/Core && swift test --filter "InstallingAnUpdate|PathsSurviveTheShell"
```
Expected: PASS, eight tests.

- [ ] **Step 6: Mutation-test the guard that matters**

Prove `adownloadThatDoesNotMatchIsNotInstalled` would catch a verification step that stopped verifying:

```bash
python3 - <<'PY'
import pathlib
p = pathlib.Path("Packages/Core/Sources/Updates/UpdateInstaller.swift")
t = p.read_text()
p.write_text(t.replace("        guard actual == expected else {", "        guard false else {"))
PY
cd Packages/Core && swift test --filter InstallingAnUpdate
```
Expected: FAIL, on `adownloadThatDoesNotMatchIsNotInstalled`. Restore:

```bash
python3 - <<'PY'
import pathlib
p = pathlib.Path("Packages/Core/Sources/Updates/UpdateInstaller.swift")
t = p.read_text()
p.write_text(t.replace("        guard false else {", "        guard actual == expected else {"))
PY
cd Packages/Core && swift test --filter InstallingAnUpdate
```
Expected: PASS.

- [ ] **Step 7: Run the whole suite**

```bash
make test
```
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Packages/Core/Sources/Updates/UpdateInstaller.swift \
        Packages/Core/Sources/Updates/Checksums.swift \
        Packages/Core/Tests/UpdatesTests/UpdateInstallerTests.swift
git commit -F - <<'MSG'
updates: download, check, and put it where the old one was

Four refusals between a release and an installed app: the bytes are the ones
published, the archive opens into a bundle, that bundle is Softcap at the
version the release claimed, and — for a build signed with a Developer ID —
it is signed by the same team.

They are the only checks there are, which is why they are all refusals.
URLSession does not mark a download with com.apple.quarantine the way a
browser does, so Gatekeeper never looks at it. That absence is the feature:
an update that opens without the dialog an ad-hoc signed build otherwise
gets. It is also the reason nothing downstream will catch what these miss.

The signature check does nothing for an ad-hoc build, and the comment says so
rather than implying a check that did not run.

Replacement is atomic within the volume: the new copy is staged beside the
installed app, not in the temporary directory, because replaceItemAt is only
atomic on one volume and a bundle half-moved across one is an app that will
not launch. The relaunch waits for this process to exit — open on a bundle
whose app is still running activates the copy in memory, and the update would
look as though it had not happened.
MSG
```

---

### Task 8: Two settings, and the app's own state

**Files:**
- Modify: `Packages/Core/Sources/Preferences/Preferences.swift`
- Test: `Packages/Core/Tests/PreferencesTests/PreferencesTests.swift`
- Create: `App/UpdateModel.swift`

**Interfaces:**
- Consumes: everything from Tasks 2–7
- Produces:
  - `Preferences.checksForUpdates: Bool` (default `true`), `Preferences.lastUpdateCheck: Date?`
  - `UpdateModel` with `@Published state`, `func checkIfDue()`, `func check()`, `func install()`
  - `UpdateModel.State`: `.idle`, `.checking`, `.upToDate`, `.available(Release)`, `.installing(UpdateInstaller.Phase)`, `.failed(UpdateFailure)`
  - `UpdateModel.runningVersion: ReleaseVersion?`, `UpdateModel.versionText: String`

- [ ] **Step 1: Write the failing test**

Add to `Packages/Core/Tests/PreferencesTests/PreferencesTests.swift`:

```swift
    /// A settings blob written before these two existed must not lose the other
    /// twenty on the way in. `Preferences` decodes field by field for exactly
    /// this, and every added setting is a chance to forget it.
    @Test func settingsWrittenBeforeUpdatesExistedStillLoad() throws {
        let old = """
            {"appearance": "dark", "menuBarContent": "percent", "thresholds": [90],
             "backgroundInterval": 600}
            """
        let decoded = try JSONDecoder().decode(Preferences.self, from: Data(old.utf8))

        #expect(decoded.appearance == .dark)
        #expect(decoded.menuBarContent == .percent)
        #expect(decoded.backgroundInterval == 600)
        #expect(decoded.checksForUpdates, "a setting from before the field existed lost its default")
        #expect(decoded.lastUpdateCheck == nil)
    }

    @Test func theAppLooksForUpdatesUnlessItIsToldNotTo() {
        #expect(Preferences.defaults.checksForUpdates)
        #expect(Preferences.defaults.lastUpdateCheck == nil)
    }
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd Packages/Core && swift test --filter PreferencesTests
```
Expected: FAIL — `value of type 'Preferences' has no member 'checksForUpdates'`.

- [ ] **Step 3: Add the fields**

In `Packages/Core/Sources/Preferences/Preferences.swift`:

Rename the comment `// Updates and launch` to `// Polling and launch` — it names a settings screen that is about to be renamed for the same reason.

Add a new group after it:

```swift
    // Updates
    public var checksForUpdates: Bool
    /// When the app last asked GitHub. `nil` means it never has.
    public var lastUpdateCheck: Date?
```

In `Preferences.defaults`, after `refreshHotKey: nil,`:

```swift
        checksForUpdates: true,
        lastUpdateCheck: nil,
```

In the hand-written `init(from decoder:)`, beside the other reads:

```swift
        checksForUpdates = read(.checksForUpdates, fallback.checksForUpdates)
        lastUpdateCheck = try? box.decodeIfPresent(Date.self, forKey: .lastUpdateCheck)
```

Match the exact spelling the surrounding lines use — read the file and follow it rather than assuming; the optional fields there have their own shape.

`noSettingIsACredential` scans for fields named `token`, `secret`, `password`, `credential`. Neither new name is one.

- [ ] **Step 4: Run the tests**

```bash
cd Packages/Core && swift test --filter "PreferencesTests|PreferencesStoreTests|NothingElseLeavesYourMac"
```
Expected: PASS.

- [ ] **Step 5: Write the app's update state**

Create `App/UpdateModel.swift`:

```swift
import Foundation
import AppKit
import Combine
import os
import ClaudeProvider
import Preferences
import Updates

/// What the app knows about a newer version, and what it is doing about it.
///
/// Held for the life of the app rather than by a view: a download that outlives
/// the settings window is the point. Closing the window mid-install does not
/// cancel it — the app comes back on its own when it is done.
@MainActor
final class UpdateModel: ObservableObject {

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case installing(UpdateInstaller.Phase)
        case failed(UpdateFailure)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastChecked: Date?

    /// Set by whoever owns the preferences, the same way `AppModel` is fed.
    var preferences: Preferences = .defaults {
        didSet { lastChecked = preferences.lastUpdateCheck }
    }

    /// Called when a check finishes, so the moment is stored where it survives
    /// a restart. The model does not own the preferences store.
    var recordCheck: ((Date) -> Void)?

    private static let owner = "milushov"
    private static let repository = "softcap"
    private static let log = Logger(subsystem: "app.softcap.Softcap", category: "updates")

    private let http: any HTTPClient
    private let downloader: any FileDownloader

    init(
        http: any HTTPClient = URLSessionHTTPClient(),
        downloader: any FileDownloader = URLSessionFileDownloader()
    ) {
        self.http = http
        self.downloader = downloader
    }

    // MARK: - what is running

    /// The version this build reports. `nil` only if the bundle has no version
    /// string at all, which no built app does.
    var runningVersion: ReleaseVersion? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            .flatMap(ReleaseVersion.init)
    }

    var versionText: String { runningVersion?.description ?? "—" }

    var releasePage: URL {
        ReleaseFeed.releasePage(owner: Self.owner, repository: Self.repository)
    }

    /// The version to offer, when there is one. Read by the menu and the footer.
    var availableVersion: ReleaseVersion? {
        if case .available(let release) = state { return release.version }
        return nil
    }

    // MARK: - checking

    /// The quiet check: at launch, and a day apart after that.
    func checkIfDue(now: Date) async {
        guard preferences.checksForUpdates else { return }
        guard UpdateSchedule.isDue(lastChecked: preferences.lastUpdateCheck, now: now) else {
            return
        }
        await check(now: now, announcing: false)
    }

    /// The check somebody asked for. Says "up to date" where the quiet one says
    /// nothing.
    func check(now: Date) async {
        await check(now: now, announcing: true)
    }

    private func check(now: Date, announcing: Bool) async {
        if case .installing = state { return }
        if announcing { state = .checking }

        guard let running = runningVersion else {
            Self.log.error("the bundle carries no version, so nothing can be compared")
            state = .failed(UpdateFailure(kind: .malformedRelease, diagnostic: "no bundle version"))
            return
        }

        let url = ReleaseFeed.latestURL(owner: Self.owner, repository: Self.repository)
        do {
            let (data, status) = try await http.get(url, headers: [
                "Accept": "application/vnd.github+json",
            ])
            guard status == 200 else {
                throw UpdateFailure(kind: .network, diagnostic: "releases came back \(status)")
            }
            let found = try ReleaseFeed.update(from: data, running: running)
            recordCheck?(now)
            lastChecked = now

            if let found {
                Self.log.info("a newer release: \(found.version.description, privacy: .public)")
                state = .available(found)
            } else if announcing {
                state = .upToDate
            } else {
                state = .idle
            }
        } catch let failure as UpdateFailure {
            report(failure, announcing: announcing)
        } catch let failure as ProviderFailure {
            report(UpdateFailure(kind: .network, diagnostic: failure.diagnostic),
                   announcing: announcing)
        } catch {
            report(UpdateFailure(kind: .network, diagnostic: "\(type(of: error))"),
                   announcing: announcing)
        }
    }

    /// A check nobody asked for does not report its failure on screen. The one
    /// somebody pressed a button for does — a button that does nothing visible
    /// reads as broken.
    private func report(_ failure: UpdateFailure, announcing: Bool) {
        Self.log.error("""
            update check failed: \(failure.diagnostic, privacy: .public)
            """)
        state = announcing ? .failed(failure) : .idle
    }

    // MARK: - installing

    func install() async {
        guard case .available(let release) = state else { return }

        let bundle = Bundle.main.bundleURL
        let installer = UpdateInstaller(downloader: downloader, http: http)
        state = .installing(.downloading(0))

        do {
            try await installer.install(release, replacing: bundle) { phase in
                Task { @MainActor [weak self] in self?.state = .installing(phase) }
            }
        } catch let failure as UpdateFailure {
            Self.log.error("install failed: \(failure.diagnostic, privacy: .public)")
            state = .failed(failure)
            return
        } catch {
            state = .failed(UpdateFailure(kind: .unpackFailed, diagnostic: "\(type(of: error))"))
            return
        }

        Self.log.info("installed \(release.version.description, privacy: .public), restarting")
        UpdateInstaller.restart(bundle)
        NSApp.terminate(nil)
    }
}
```

- [ ] **Step 6: Hold it in the delegate**

In `App/SoftcapApp.swift`, add to `AppDelegate`:

```swift
    let updates = UpdateModel()
```

and inside `applicationDidFinishLaunching`, after `model.preferences = preferences.value`:

```swift
            updates.preferences = preferences.value
            updates.recordCheck = { [preferences] moment in
                preferences.update { $0.lastUpdateCheck = moment }
            }
            // The quiet check. It opens nothing: at most it changes the words
            // on a menu item and in the settings footer.
            Task { await updates.checkIfDue(now: Date()) }
```

and in the `Settings` scene, alongside the existing `onChange` that feeds `delegate.model`:

```swift
                .onChange(of: delegate.preferences.value, initial: true) { _, new in
                    delegate.updates.preferences = new
                }
```

Check `PreferencesModel.update`'s exact signature in `App/PreferencesModel.swift` before writing the closure, and follow it.

- [ ] **Step 7: Build**

```bash
make build
```
Expected: BUILD SUCCEEDED. The `Updates` product must be added to the `Softcap` target's dependencies in `project.yml` first:

```yaml
      - package: Core
        product: Updates
```

Add it to the `Softcap` target only — not to `SoftcapWidget`, `SoftcapiOS` or `SoftcapiOSWidget`.

- [ ] **Step 8: Run the whole suite**

```bash
make test
```
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add Packages/Core/Sources/Preferences/Preferences.swift \
        Packages/Core/Tests/PreferencesTests/PreferencesTests.swift \
        App/UpdateModel.swift App/SoftcapApp.swift project.yml
git commit -F - <<'MSG'
updates: the check the app runs on its own

Two settings — whether to look, and when it last did — and the state around
them. The check runs at launch and a day apart after that, and opens nothing:
at most it changes the words on a menu item and in the settings footer.

A check nobody asked for keeps its failures in the log. The one somebody
pressed a button for puts them on screen, because a button that does nothing
visible reads as broken.

The model outlives the settings window on purpose. Closing the window during
an install does not cancel it; the app comes back on its own when it is done.
MSG
```

---

### Task 9: The Updates screen, and the pane that had its name

**Files:**
- Create: `App/Settings/PollingPane.swift` (the old `UpdatesPane`, renamed)
- Modify: `App/Settings/UpdatesPane.swift` (replaced content — the new screen)
- Modify: `App/Settings/SettingsIcons.swift`
- Modify: `App/Settings/SettingsView.swift`
- Modify: `App/AppModel.swift`
- Modify: the ten catalogues

**Interfaces:**
- Consumes: `UpdateModel` (Task 8)
- Produces:
  - `SettingsSection.polling` and `SettingsSection.updates`
  - `AppModel.settingsSection: SettingsSection`
  - `UpdatesPane(updates:model:)`, `PollingPane(model:)`

- [ ] **Step 1: Rename the existing pane**

```bash
git mv App/Settings/UpdatesPane.swift App/Settings/PollingPane.swift
```

In `App/Settings/PollingPane.swift`, rename the type and retitle the screen:

```swift
struct PollingPane: View {
```

and

```swift
        Pane(title: loc("Polling and launch"),
             subtitle: loc("How often to fetch data and whether to start on its own.")) {
```

Everything else in the file stays.

- [ ] **Step 2: Add the sections**

In `App/Settings/SettingsIcons.swift`:

```swift
enum SettingsSection: String, CaseIterable, Identifiable {
    case accounts, statistics, appearance, notifications, polling, updates, services, about
```

```swift
        case .polling:       "Polling and launch"
        case .updates:       "Updates"
```

```swift
        // An arrow going round is what polling looks like; an arrow coming down
        // is what an update is. The old screen held the first symbol under the
        // second name.
        case .polling:       "arrow.clockwise"
        case .updates:       "arrow.down.circle"
```

- [ ] **Step 3: Route the selection through the model**

In `App/AppModel.swift`, beside the other published properties:

```swift
    /// Which settings screen to show. Published rather than held by the view:
    /// the menu bar opens the window through the system's ⌘, item and has no
    /// way to reach into it otherwise.
    @Published var settingsSection: SettingsSection = .accounts
```

In `App/Settings/SettingsView.swift`, replace

```swift
    @State private var selection: SettingsSection = .accounts
```

with a binding onto the model, and use `appModel.settingsSection` in place of `selection` throughout the file — the sidebar `Button` action, the two `selection == section` comparisons, and the `switch` in `detail`.

Add the new cases to that `switch`:

```swift
                case .polling:       PollingPane(model: model)
                case .updates:       UpdatesPane(updates: updates, model: model)
```

`SettingsView` needs the update model. Add `@ObservedObject var updates: UpdateModel` beside its other properties and pass it from `App/SoftcapApp.swift`:

```swift
            SettingsView(model: delegate.preferences,
                         appModel: delegate.model,
                         updates: delegate.updates)
```

- [ ] **Step 4: Add the footer**

In `App/Settings/SettingsView.swift`, wrap the existing `HStack` in a `VStack` so the footer spans the window:

```swift
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Divider()
                detail
            }
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 720, height: 470)
```

and add:

```swift
    /// Quiet, right aligned, on every screen — which is what makes it the
    /// place people find this rather than the sidebar entry.
    private var footer: some View {
        HStack {
            Spacer()
            Button(footerTitle) { appModel.settingsSection = .updates }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Text("·").font(.system(size: 11.5)).foregroundStyle(.tertiary)
            Text(updates.versionText)
                .font(.system(size: 11.5))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var footerTitle: String {
        guard let newer = updates.availableVersion else { return loc("Check for updates") }
        return String(format: loc("Update to %@"), newer.description)
    }
```

- [ ] **Step 5: Write the Updates screen**

Replace the contents of `App/Settings/UpdatesPane.swift`:

```swift
import SwiftUI
import AppKit
import Preferences
import StatusUI
import Updates

/// Everything an update does, on one screen.
///
/// There is no sheet and no second window. A menu bar app that opens a window
/// to tell you something is a menu bar app that interrupts, and this one was
/// built not to.
struct UpdatesPane: View {
    @ObservedObject var updates: UpdateModel
    @ObservedObject var model: PreferencesModel

    @ObservedObject private var loc = Localization.shared

    var body: some View {
        Pane(title: loc("Updates"),
             subtitle: loc("Where new versions come from, and when to look for one.")) {
            Form {
                Section {
                    LabeledContent(loc("Version"), value: updates.versionText)
                    LabeledContent(loc("Last checked"), value: lastChecked)
                }

                Section { state }

                Section {
                    Toggle(loc("Check automatically"), isOn: Binding(
                        get: { model.value.checksForUpdates },
                        set: { new in model.update { $0.checksForUpdates = new } }
                    ))
                    Text(loc("Once a day, and never without saying so here first."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
        }
    }

    // MARK: -

    @ViewBuilder
    private var state: some View {
        switch updates.state {
        case .idle, .upToDate:
            HStack {
                Text(updates.state == .upToDate
                     ? loc("This is the latest version.")
                     : loc("No new version has been found."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                checkButton
            }

        case .checking:
            HStack {
                ProgressView().controlSize(.small)
                Text(loc("Checking…")).font(.system(size: 12)).foregroundStyle(.secondary)
            }

        case .available(let release):
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(String(format: loc("Version %@ is available."),
                                release.version.description))
                        .font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    Button(String(format: loc("Update to %@"), release.version.description)) {
                        Task { await updates.install() }
                    }
                    .keyboardShortcut(.defaultAction)
                }
                notes(release.notes)
            }

        case .installing(let phase):
            VStack(alignment: .leading, spacing: 8) {
                Text(title(for: phase)).font(.system(size: 12))
                progress(for: phase)
                Text(loc("The app will restart on its own when this finishes."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

        case .failed(let failure):
            VStack(alignment: .leading, spacing: 8) {
                Text(sentence(for: failure.kind))
                    .font(.system(size: 12))
                    .foregroundStyle(Severity.hot.tint)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    checkButton
                    Button(loc("Open the release page")) {
                        NSWorkspace.shared.open(updates.releasePage)
                    }
                }
            }
        }
    }

    private var checkButton: some View {
        Button(loc("Check for updates")) {
            Task { await updates.check(now: Date()) }
        }
    }

    /// The release body as its author wrote it. Markdown, and text that came
    /// over the network — rendered as text and nothing else, so a link in it
    /// cannot become a button that does something.
    private func notes(_ body: String) -> some View {
        ScrollView {
            Text(attributed(body))
                .font(.system(size: 11.5))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 150)
    }

    private func attributed(_ body: String) -> AttributedString {
        (try? AttributedString(
            markdown: body,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(body)
    }

    @ViewBuilder
    private func progress(for phase: UpdateInstaller.Phase) -> some View {
        if case .downloading(let fraction) = phase {
            ProgressView(value: fraction)
        } else {
            ProgressView().progressViewStyle(.linear)
        }
    }

    private func title(for phase: UpdateInstaller.Phase) -> String {
        switch phase {
        case .downloading: loc("Downloading…")
        case .verifying:   loc("Checking what arrived…")
        case .installing:  loc("Installing…")
        }
    }

    /// The interface builds the sentence; the model carries the identifier.
    private func sentence(for kind: UpdateFailure.Kind) -> String {
        switch kind {
        case .network:
            loc("GitHub could not be reached. Check the connection and try again.")
        case .malformedRelease:
            loc("The newest release has no build to download.")
        case .checksumMismatch:
            loc("What arrived is not what the release published, so it was discarded.")
        case .signatureChanged:
            loc("The download is signed by somebody else, so it was discarded.")
        case .notWritable:
            loc("Softcap could not be replaced where it is installed. Move it to Applications, or download it yourself.")
        case .unpackFailed:
            loc("The download could not be opened.")
        }
    }

    private var lastChecked: String {
        guard let moment = updates.lastChecked else { return loc("never") }
        return moment.formatted(date: .abbreviated, time: .shortened)
    }
}
```

- [ ] **Step 6: Add the strings**

Run from the repository root:

```bash
python3 tools/add_strings.py <<'JSON'
{
  "Updates": {"zh-Hans": "更新", "hi": "अपडेट", "es": "Actualizaciones", "ar": "التحديثات", "fr": "Mises à jour", "bn": "আপডেট", "pt-BR": "Atualizações", "ru": "Обновления", "id": "Pembaruan"}
}
JSON
```

`Updates` is already in the catalogues — the script leaves keys it finds alone, so this is harmless and keeps the command complete. The keys that are actually new:

```bash
python3 tools/add_strings.py <<'JSON'
{
  "Polling and launch": {"zh-Hans": "轮询与启动", "hi": "पोलिंग और लॉन्च", "es": "Sondeo e inicio", "ar": "الاستطلاع والتشغيل", "fr": "Interrogation et lancement", "bn": "পোলিং ও চালু", "pt-BR": "Consulta e inicialização", "ru": "Опрос и запуск", "id": "Pengambilan dan peluncuran"},
  "Where new versions come from, and when to look for one.": {"zh-Hans": "新版本从哪里来，以及何时查找。", "hi": "नए संस्करण कहाँ से आते हैं, और कब देखना है।", "es": "De dónde vienen las versiones nuevas y cuándo buscarlas.", "ar": "من أين تأتي الإصدارات الجديدة، ومتى يتم البحث عنها.", "fr": "D'où viennent les nouvelles versions, et quand les chercher.", "bn": "নতুন সংস্করণ কোথা থেকে আসে, আর কখন খোঁজা হয়।", "pt-BR": "De onde vêm as versões novas e quando procurá-las.", "ru": "Откуда берутся новые версии и когда их искать.", "id": "Dari mana versi baru berasal, dan kapan mencarinya."},
  "Last checked": {"zh-Hans": "上次检查", "hi": "पिछली जाँच", "es": "Última comprobación", "ar": "آخر فحص", "fr": "Dernière vérification", "bn": "শেষ পরীক্ষা", "pt-BR": "Última verificação", "ru": "Последняя проверка", "id": "Terakhir diperiksa"},
  "never": {"zh-Hans": "从未", "hi": "कभी नहीं", "es": "nunca", "ar": "أبدًا", "fr": "jamais", "bn": "কখনও নয়", "pt-BR": "nunca", "ru": "никогда", "id": "belum pernah"},
  "Check for updates": {"zh-Hans": "检查更新", "hi": "अपडेट देखें", "es": "Buscar actualizaciones", "ar": "التحقق من التحديثات", "fr": "Rechercher des mises à jour", "bn": "আপডেট দেখুন", "pt-BR": "Buscar atualizações", "ru": "Проверить обновления", "id": "Periksa pembaruan"},
  "Check for updates…": {"zh-Hans": "检查更新…", "hi": "अपडेट देखें…", "es": "Buscar actualizaciones…", "ar": "التحقق من التحديثات…", "fr": "Rechercher des mises à jour…", "bn": "আপডেট দেখুন…", "pt-BR": "Buscar atualizações…", "ru": "Проверить обновления…", "id": "Periksa pembaruan…"},
  "Update to %@": {"zh-Hans": "更新到 %@", "hi": "%@ में अपडेट करें", "es": "Actualizar a %@", "ar": "التحديث إلى %@", "fr": "Mettre à jour vers %@", "bn": "%@ এ আপডেট করুন", "pt-BR": "Atualizar para %@", "ru": "Обновить до %@", "id": "Perbarui ke %@"},
  "Version %@ is available.": {"zh-Hans": "%@ 版本可用。", "hi": "संस्करण %@ उपलब्ध है।", "es": "La versión %@ está disponible.", "ar": "الإصدار %@ متاح.", "fr": "La version %@ est disponible.", "bn": "সংস্করণ %@ পাওয়া যাচ্ছে।", "pt-BR": "A versão %@ está disponível.", "ru": "Доступна версия %@.", "id": "Versi %@ tersedia."},
  "This is the latest version.": {"zh-Hans": "这已是最新版本。", "hi": "यह नवीनतम संस्करण है।", "es": "Esta es la versión más reciente.", "ar": "هذا هو أحدث إصدار.", "fr": "C'est la version la plus récente.", "bn": "এটিই সর্বশেষ সংস্করণ।", "pt-BR": "Esta é a versão mais recente.", "ru": "Это последняя версия.", "id": "Ini versi terbaru."},
  "No new version has been found.": {"zh-Hans": "尚未发现新版本。", "hi": "कोई नया संस्करण नहीं मिला।", "es": "No se ha encontrado ninguna versión nueva.", "ar": "لم يتم العثور على إصدار جديد.", "fr": "Aucune nouvelle version n'a été trouvée.", "bn": "নতুন কোনো সংস্করণ পাওয়া যায়নি।", "pt-BR": "Nenhuma versão nova foi encontrada.", "ru": "Новая версия не найдена.", "id": "Tidak ada versi baru yang ditemukan."},
  "Checking…": {"zh-Hans": "正在检查…", "hi": "जाँच हो रही है…", "es": "Comprobando…", "ar": "جارٍ التحقق…", "fr": "Vérification…", "bn": "পরীক্ষা করা হচ্ছে…", "pt-BR": "Verificando…", "ru": "Проверяем…", "id": "Memeriksa…"},
  "Downloading…": {"zh-Hans": "正在下载…", "hi": "डाउनलोड हो रहा है…", "es": "Descargando…", "ar": "جارٍ التنزيل…", "fr": "Téléchargement…", "bn": "ডাউনলোড হচ্ছে…", "pt-BR": "Baixando…", "ru": "Загружаем…", "id": "Mengunduh…"},
  "Checking what arrived…": {"zh-Hans": "正在核对下载内容…", "hi": "जो आया उसकी जाँच…", "es": "Comprobando lo descargado…", "ar": "جارٍ فحص ما وصل…", "fr": "Vérification du téléchargement…", "bn": "যা এসেছে তা যাচাই হচ্ছে…", "pt-BR": "Conferindo o que chegou…", "ru": "Сверяем загруженное…", "id": "Memeriksa yang diunduh…"},
  "Installing…": {"zh-Hans": "正在安装…", "hi": "इंस्टॉल हो रहा है…", "es": "Instalando…", "ar": "جارٍ التثبيت…", "fr": "Installation…", "bn": "ইনস্টল হচ্ছে…", "pt-BR": "Instalando…", "ru": "Устанавливаем…", "id": "Memasang…"},
  "The app will restart on its own when this finishes.": {"zh-Hans": "完成后应用会自行重启。", "hi": "पूरा होने पर ऐप खुद फिर से चालू हो जाएगा।", "es": "La app se reiniciará sola al terminar.", "ar": "سيعيد التطبيق تشغيل نفسه عند الانتهاء.", "fr": "L'app redémarrera d'elle-même à la fin.", "bn": "শেষ হলে অ্যাপ নিজেই আবার চালু হবে।", "pt-BR": "O app reinicia sozinho ao terminar.", "ru": "Приложение перезапустится само, когда закончит.", "id": "Aplikasi akan memulai ulang sendiri setelah selesai."},
  "Check automatically": {"zh-Hans": "自动检查", "hi": "अपने आप जाँचें", "es": "Comprobar automáticamente", "ar": "التحقق تلقائيًا", "fr": "Vérifier automatiquement", "bn": "নিজে থেকে পরীক্ষা করুক", "pt-BR": "Verificar automaticamente", "ru": "Проверять автоматически", "id": "Periksa otomatis"},
  "Once a day, and never without saying so here first.": {"zh-Hans": "每天一次，并且总会先在这里说明。", "hi": "दिन में एक बार, और हमेशा पहले यहाँ बताकर।", "es": "Una vez al día, y nunca sin decirlo aquí antes.", "ar": "مرة واحدة يوميًا، ولا يحدث ذلك دون ذكره هنا أولًا.", "fr": "Une fois par jour, et jamais sans le dire ici d'abord.", "bn": "দিনে একবার, আর সবসময় আগে এখানে জানিয়ে।", "pt-BR": "Uma vez por dia, e nunca sem dizer isso aqui antes.", "ru": "Раз в сутки, и никогда не молча — здесь об этом сказано.", "id": "Sekali sehari, dan tidak pernah tanpa disebutkan di sini dulu."},
  "GitHub could not be reached. Check the connection and try again.": {"zh-Hans": "无法连接 GitHub。请检查网络后重试。", "hi": "GitHub तक नहीं पहुँच सके। कनेक्शन जाँचकर फिर कोशिश करें।", "es": "No se pudo acceder a GitHub. Comprueba la conexión e inténtalo otra vez.", "ar": "تعذّر الوصول إلى GitHub. تحقّق من الاتصال وحاول مرة أخرى.", "fr": "GitHub est injoignable. Vérifiez la connexion et réessayez.", "bn": "GitHub-এ পৌঁছনো গেল না। সংযোগ দেখে আবার চেষ্টা করুন।", "pt-BR": "Não foi possível acessar o GitHub. Verifique a conexão e tente de novo.", "ru": "Не удалось связаться с GitHub. Проверьте соединение и попробуйте снова.", "id": "GitHub tidak dapat dihubungi. Periksa koneksi lalu coba lagi."},
  "The newest release has no build to download.": {"zh-Hans": "最新发布里没有可下载的版本。", "hi": "नवीनतम रिलीज़ में डाउनलोड करने योग्य बिल्ड नहीं है।", "es": "La versión más reciente no trae ningún archivo para descargar.", "ar": "أحدث إصدار لا يحتوي على نسخة قابلة للتنزيل.", "fr": "La dernière version ne contient aucun fichier à télécharger.", "bn": "সর্বশেষ রিলিজে ডাউনলোড করার মতো কিছু নেই।", "pt-BR": "A versão mais recente não traz nenhum arquivo para baixar.", "ru": "В последнем релизе нечего скачивать.", "id": "Rilis terbaru tidak memuat berkas untuk diunduh."},
  "What arrived is not what the release published, so it was discarded.": {"zh-Hans": "下载到的内容与发布的不符，已丢弃。", "hi": "जो आया वह रिलीज़ में प्रकाशित से मेल नहीं खाता, इसलिए हटा दिया गया।", "es": "Lo descargado no coincide con lo publicado, así que se descartó.", "ar": "ما وصل لا يطابق ما نشره الإصدار، لذلك تم تجاهله.", "fr": "Le fichier reçu ne correspond pas à celui publié : il a été écarté.", "bn": "যা এসেছে তা প্রকাশিতটির সঙ্গে মেলেনি, তাই বাতিল করা হয়েছে।", "pt-BR": "O que chegou não confere com o publicado, então foi descartado.", "ru": "Пришло не то, что опубликовано в релизе, — загрузка отброшена.", "id": "Yang diunduh tidak cocok dengan yang dirilis, jadi dibuang."},
  "The download is signed by somebody else, so it was discarded.": {"zh-Hans": "下载内容由他人签名，已丢弃。", "hi": "डाउनलोड किसी और के हस्ताक्षर से आया है, इसलिए हटा दिया गया।", "es": "La descarga está firmada por otra persona, así que se descartó.", "ar": "التنزيل موقَّع من شخص آخر، لذلك تم تجاهله.", "fr": "Le téléchargement est signé par quelqu'un d'autre : il a été écarté.", "bn": "ডাউনলোডটি অন্য কারও স্বাক্ষরে এসেছে, তাই বাতিল করা হয়েছে।", "pt-BR": "O download está assinado por outra pessoa, então foi descartado.", "ru": "Загрузка подписана кем-то другим — она отброшена.", "id": "Unduhan ditandatangani orang lain, jadi dibuang."},
  "Softcap could not be replaced where it is installed. Move it to Applications, or download it yourself.": {"zh-Hans": "无法替换已安装位置上的 Softcap。请将它移到「应用程序」，或自行下载。", "hi": "Softcap जहाँ इंस्टॉल है वहाँ बदला नहीं जा सका। इसे Applications में ले जाएँ, या खुद डाउनलोड करें।", "es": "No se pudo reemplazar Softcap donde está instalado. Muévelo a Aplicaciones o descárgalo tú mismo.", "ar": "تعذّر استبدال Softcap في مكان تثبيته. انقله إلى مجلد التطبيقات، أو نزّله بنفسك.", "fr": "Softcap n'a pas pu être remplacé là où il est installé. Déplacez-le vers Applications, ou téléchargez-le vous-même.", "bn": "Softcap যেখানে ইনস্টল করা, সেখানে বদলানো গেল না। এটিকে Applications-এ সরান, বা নিজে ডাউনলোড করুন।", "pt-BR": "Não foi possível substituir o Softcap onde ele está instalado. Mova-o para Aplicativos ou baixe você mesmo.", "ru": "Не удалось заменить Softcap там, где он установлен. Перенесите его в «Программы» или скачайте вручную.", "id": "Softcap tidak bisa diganti di tempat ia terpasang. Pindahkan ke Applications, atau unduh sendiri."},
  "The download could not be opened.": {"zh-Hans": "无法打开下载的文件。", "hi": "डाउनलोड खोला नहीं जा सका।", "es": "No se pudo abrir la descarga.", "ar": "تعذّر فتح الملف الذي تم تنزيله.", "fr": "Le téléchargement n'a pas pu être ouvert.", "bn": "ডাউনলোডটি খোলা গেল না।", "pt-BR": "Não foi possível abrir o download.", "ru": "Загруженный файл не открылся.", "id": "Berkas unduhan tidak bisa dibuka."},
  "Open the release page": {"zh-Hans": "打开发布页面", "hi": "रिलीज़ पेज खोलें", "es": "Abrir la página de la versión", "ar": "فتح صفحة الإصدار", "fr": "Ouvrir la page de la version", "bn": "রিলিজ পাতা খুলুন", "pt-BR": "Abrir a página da versão", "ru": "Открыть страницу релиза", "id": "Buka halaman rilis"}
}
JSON
```

Check the script's output: it prints what it added and refuses a key missing a language.

- [ ] **Step 7: Build and run the app**

```bash
make run
```

Open the settings window from the menu bar icon and confirm by eye:
- the sidebar has **Polling and launch** and **Updates**, in that order, with the round arrow on the first and the down arrow on the second
- the footer sits under both columns, right aligned, reading `Check for updates · 0.1`
- clicking the footer selects the Updates screen
- the Updates screen shows the version, `never` for the last check, and a Check button
- switching the interface language changes every one of those without a restart

- [ ] **Step 8: Run the whole suite**

```bash
make test
```
Expected: PASS. `NoOrphanStrings` is the one to watch: it fails if any key added in Step 6 is not written as a literal at a call site.

- [ ] **Step 9: Commit**

```bash
git add App/Settings App/AppModel.swift App/SoftcapApp.swift \
        Packages/Core/Sources/StatusUI/Resources
git commit -F - <<'MSG'
updates: a screen for updates, and a name given back

The sidebar already had a screen called Updates. It was about poll frequency,
launch at login and hot keys — so app updates would have had to live under
About while Updates meant something else. It is now Polling and launch, and
its round-arrow icon suits that better than it ever suited updating.

The new screen holds the whole flow: the version, the notes, the button, the
progress. No sheet and no second window. A menu bar app that opens a window
to tell you something is one that interrupts, and this one was built not to —
which also means closing the window during an install cannot cancel it.

The footer is the surface people will actually find: quiet, right aligned,
on every screen, and it says which version this is whether or not there is a
newer one.

Selecting a screen goes through AppModel. SettingsWindow reaches the window
through the system's ⌘, menu item and owns none of its state, so the menu bar
had no other way to open the app on a particular screen.
MSG
```

---

### Task 10: The menu

**Files:**
- Modify: `App/StatusItemController.swift`
- Modify: the ten catalogues

**Interfaces:**
- Consumes: `UpdateModel`, `SettingsSection`
- Produces: nothing further

- [ ] **Step 1: Give the controller the update model**

In `App/StatusItemController.swift`, add a stored property and take it in `init`:

```swift
    private let updates: UpdateModel
```

```swift
    init(model: AppModel, preferences: PreferencesModel, updates: UpdateModel) {
        self.model = model
        self.preferences = preferences
        self.updates = updates
        super.init()
    }
```

and in `App/SoftcapApp.swift`:

```swift
    private lazy var statusItem = StatusItemController(
        model: model, preferences: preferences, updates: updates)
```

- [ ] **Step 2: Build the menu**

In `showMenu(from:)`, before the existing `refresh` item:

```swift
        // The version, as a heading rather than an action. Disabled on purpose:
        // it is a label, and a menu item that looks clickable and is not is
        // worse than one that plainly is not.
        let version = NSMenuItem(
            title: String(format: Localization.shared("Softcap %@"), updates.versionText),
            action: nil, keyEquivalent: ""
        )
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(.separator())
```

and after the `settings` item, before the separator that precedes Quit:

```swift
        // Reads as an offer once there is one to make. This is the whole of how
        // loudly a found update announces itself.
        let update = NSMenuItem(
            title: updates.availableVersion.map {
                String(format: Localization.shared("Update to %@"), $0.description)
            } ?? Localization.shared("Check for updates…"),
            action: #selector(openUpdates), keyEquivalent: ""
        )
        update.target = self
        menu.addItem(update)
```

and add the action beside `openSettings`:

```swift
    @objc private func openUpdates() {
        model.settingsSection = .updates
        SettingsWindow.open()
        // Asked for by hand, so it says "up to date" rather than going quiet.
        Task { await updates.check(now: Date()) }
    }
```

`NSMenu` disables items with no target by default via `autoenablesItems`; setting `isEnabled = false` on an item whose action is `nil` is belt and braces and matches what the heading is for.

- [ ] **Step 3: Add the string**

```bash
python3 tools/add_strings.py <<'JSON'
{
  "Softcap %@": {"zh-Hans": "Softcap %@", "hi": "Softcap %@", "es": "Softcap %@", "ar": "Softcap %@", "fr": "Softcap %@", "bn": "Softcap %@", "pt-BR": "Softcap %@", "ru": "Softcap %@", "id": "Softcap %@"}
}
JSON
```

The brand name and a number: the same in every language, and `BrandNamesAreCapitalised` requires the capital.

- [ ] **Step 4: Build and look**

```bash
make run
```

Right-click the menu bar icon and confirm:
- the first item reads `Softcap 0.1`, dimmed, and does nothing when clicked
- `Check for updates…` sits under `Settings…`
- it opens the settings window on the Updates screen and starts a check
- `Quit Softcap` still has ⌘Q and `Refresh` still has ⌘R

- [ ] **Step 5: Run the whole suite**

```bash
make test
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add App/StatusItemController.swift App/SoftcapApp.swift \
        Packages/Core/Sources/StatusUI/Resources
git commit -F - <<'MSG'
updates: the version at the top of the menu, and the offer under Settings

The right-click menu gains a dimmed heading with the version — the fastest
answer to "which build is this" for an app with no Dock icon and no About
item in a menu bar of its own.

The update item reads "Check for updates…" until there is something to offer
and "Update to 0.1.47" once there is. That change, and the same one in the
settings footer, is the whole of how loudly a found update announces itself:
no notification, no badge, no window opening by itself.

Choosing it opens the settings window on the Updates screen and starts a
check, so an item somebody pressed says "this is the latest version" rather
than going quiet.
MSG
```

---

### Task 11: The record

**Files:**
- Modify: `docs/DECISIONS.md`
- Modify: `README.md`

- [ ] **Step 1: Append the decision entry**

Add to the end of `docs/DECISIONS.md`, following the shape of the entries above it — a heading, then **Decision**, **Why**, **Cost**. Cover, in this order:

1. **Its own updater rather than Sparkle.** Sparkle's window carries its own strings and follows the system language, while every label in this app follows a switcher that needs no restart. That seam, and a first external dependency, against roughly four hundred lines of our own. Note that the download not being quarantined — `URLSession` marks nothing — is what removes the Gatekeeper dialog an ad-hoc build otherwise gets, and that this is a consequence rather than the reason.

2. **What the verification is worth.** The checksum comes from the same origin as the file: it catches a corrupted download, not a compromised GitHub, because whoever could replace one could replace the other. TLS and trusting GitHub are what stand behind it, which is the same trust the project already asks of anyone downloading the image by hand. The signature check is the one that would notice a swapped bundle and it does nothing for an ad-hoc build. Say this plainly — the entry exists so that nobody later reads the code and believes more was checked than was.

3. **The landing sentence.** It promised "nothing else leaves your Mac" and a version check leaves. Record that `NothingElseLeavesYourMac.everyHostIsOneWeNamed` is what forced the question, and that a guard whose whole job is to make somebody notice earned its keep the first time it fired.

4. **The version literal in `project.yml`.** Every published build called itself `0.1` because the app target wrote the version out while the widget beside it took it from the build setting. Record that nothing read the number, which is why it cost nothing, and that a feature reading it was what made it visible.

5. **Two screens, one name.** Why the poll-frequency screen was renamed rather than app updates being put under About.

- [ ] **Step 2: Add a paragraph to the README**

Under **Install**, after the block the release workflow rewrites, add:

```markdown
Once it is running, Softcap updates itself. It asks GitHub for the newest
release once a day, and says so in two places and nowhere else: the version
line at the top of the right-click menu, and the footer of the settings window.
Nothing opens on its own. The Updates screen has the switch that turns the
check off.

An update it installs itself does not go through the browser, so macOS does not
quarantine it and the first-launch dialog above does not come back.
```

`ReadmeQuotesTheCode` and `LandingMatchesApp` both read this file — run the suite after editing.

- [ ] **Step 3: Refresh the decision index**

```bash
tools/decisions-index
```

Its output is checked by a guard test; follow whatever it prints.

- [ ] **Step 4: Run the whole suite**

```bash
make test
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add docs/DECISIONS.md README.md
git commit -F - <<'MSG'
docs: what the updater checks, and what it does not

Five entries. The one that matters is the second: the checksum comes from the
same origin as the file, so it catches a corrupted download and not a
compromised GitHub — whoever could replace one could replace the other. The
signature check is the one that would notice a swapped bundle and it does
nothing for an ad-hoc build.

That is written down so nobody later reads the code and believes more was
checked than was. The interface says the same thing, in fewer words.

Also recorded: why Sparkle was not used, why the landing's promise had to
change, and that the host check is what forced the question — a guard whose
whole job is to make somebody notice, earning its keep the first time it
fired.
MSG
```

---

## Self-Review

**Spec coverage.** Every section of the spec has a task: the version literal (1), `ReleaseVersion` (2), `Checksums` (3), `UpdateSchedule` and its guard (4), `ReleaseFeed` (5), `FileDownloader` and the host list and the landing sentence (6), `UpdateInstaller` and its behavioural guards (7), preferences and the check (8), the screen and both renames (9), the menu and the footer (9–10), the decision log and README (11).

**Two departures from the spec, both deliberate.**

The spec listed `UpdateFailure.signatureChanged` among the identifiers but did not say a release missing `SHA256SUMS.txt` should be refused. Task 5 refuses it as `.malformedRelease`: without the sums there is nothing to verify against, and the alternative is installing unverified, which contradicts the spec's own step 2.

The spec did not mention `Checksums.digest(ofFileAt:)`. It is added in Task 7 because the verification needs it and it belongs beside the parser that produces the value it is compared with.

**Type consistency.** `ReleaseVersion.description` is used by the menu, the footer and the pane. `UpdateInstaller.Phase` is produced in Task 7 and consumed in Tasks 8 and 9 under the same three cases. `UpdateModel.versionText` and `availableVersion` are defined in Task 8 and used in Tasks 9 and 10. `SettingsSection.polling` is added in Task 9 and never named earlier. `FileDownloader.download(_:progress:)` has one signature across Tasks 6, 7 and 8.

**One thing an implementer must check rather than assume.** `Preferences.init(from decoder:)` is hand-written and its helper is named `read` in the excerpt this plan quotes, but the optional fields in it have their own shape. Task 8 Step 3 says to read the file and follow it; do that rather than pasting.
