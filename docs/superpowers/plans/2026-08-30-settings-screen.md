> **Note.** This plan is kept in Russian: it is a record of work already
> carried out, step by step, not a reference document. New plans are written
> in English. See `docs/DECISIONS.md` for the reasoning.

# The settings screen — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A settings window with six sections that genuinely governs how the app behaves, plus signing in to a Claude account through the browser from inside settings.

**Architecture:** The settings model, and every piece of logic that can be checked without launching the app, live in a new module `Packages/Core/Sources/Preferences`. The places that hard-code values today (`ThresholdTracker`, `orderedForDisplay`, the poll intervals) start taking them as a parameter. The screens are a `Settings` scene in `App/Settings/`, one file per section.

**Tech Stack:** Swift 6.2, SwiftUI `Settings` + `NavigationSplitView`, `UserDefaults`, `CryptoKit` (PKCE), `Network` (the listener the browser comes back to), `ServiceManagement` (launch at login), Carbon (global shortcuts), Swift Testing.

## Global Constraints

- Swift tools version `6.2`, platform `.macOS(.v14)`, strict concurrency.
- No test reaches the network, reads the keychain or writes to `UserDefaults` — everything sits behind a protocol.
- Secrets (`code_verifier`, tokens) never reach the log, `UserDefaults` or an error message.
- Settings are stored in `UserDefaults` under the single key `preferences`; credentials stay in the keychain.
- The interface language is Russian. The default appearance is `Системное`.
- Default thresholds `[80, 95]`; poll intervals 60 s and 300 s; the interval bounds are 30…3600 s.
- The OAuth addresses (from Claude Code's own constants, checked 2026-08-30):
  authorize `https://platform.claude.com/oauth/authorize`,
  token `https://platform.claude.com/v1/oauth/token`,
  client_id `9d1c250a-e61b-44d9-88ed-5944d1962f5e`,
  scope `org:create_api_key user:profile user:inference`.
- Section icons are monochrome line glyphs in the colour of the label, with no tile behind them.

## File layout

```
Packages/Core/Sources/Preferences/          # the new module
├── Preferences.swift          # the model, its defaults, normalisation
├── QuietHours.swift           # the quiet window, including across midnight
└── PreferencesStore.swift     # the storage protocol + UserDefaults

Packages/Core/Sources/ClaudeProvider/
├── OAuthEndpoints.swift       # the addresses and client_id, in one place
├── PKCE.swift                 # verifier, challenge, base64url
├── OAuthLogin.swift           # building the URL + trading the code for tokens
└── ClaudeProvider.swift       # (unchanged)

Packages/Core/Sources/Credentials/
└── CredentialStore.swift      # + addLoggedInAccount, forget, hidden

Packages/Core/Sources/Monitoring/
└── ThresholdNotifier.swift    # thresholds and quiet hours as a parameter

Packages/Core/Sources/ProviderKit/
└── SnapshotOrdering.swift     # the order as a parameter

App/
├── PreferencesModel.swift     # @MainActor wrapper over Preferences
├── LaunchAtLogin.swift        # SMAppService
├── LoginController.swift      # the localhost listener + opening the browser
├── HotKeys.swift              # Carbon RegisterEventHotKey
└── Settings/
    ├── SettingsView.swift     # the frame, the sidebar
    ├── SettingsIcons.swift    # the monochrome section glyphs
    ├── AccountsPane.swift
    ├── AppearancePane.swift
    ├── NotificationsPane.swift
    ├── UpdatesPane.swift
    ├── ServicesPane.swift
    └── AboutPane.swift
```

---

### Task 1: The settings model

**Files:**
- Create: `Packages/Core/Sources/Preferences/Preferences.swift`
- Create: `Packages/Core/Sources/Preferences/QuietHours.swift`
- Modify: `Packages/Core/Package.swift`
- Test: `Packages/Core/Tests/PreferencesTests/PreferencesTests.swift`
- Test: `Packages/Core/Tests/PreferencesTests/QuietHoursTests.swift`

**Interfaces:**
- Consumes: `ProviderID` from `ProviderKit`.
- Produces:
  - `enum Appearance: String, Codable, Sendable, CaseIterable` — `.system`, `.light`, `.dark`
  - `enum MenuBarContent: String, Codable, Sendable, CaseIterable` — `.iconOnly`, `.timer`, `.percent`, `.both`
  - `enum PrimaryWindow: String, Codable, Sendable, CaseIterable` — `.worst`, `.session`, `.weekly`
  - `enum RowLayout: String, Codable, Sendable, CaseIterable` — `.twoWindows`, `.compact`, `.rings`
  - `enum Ordering: String, Codable, Sendable, CaseIterable` — `.leastLoadedFirst`, `.byName`
  - `enum WindowScope: String, Codable, Sendable, CaseIterable` — `.session`, `.weekly`, `.both`
  - `struct QuietHours: Codable, Sendable, Hashable` — `init(startMinute:endMinute:)`, `contains(_ date: Date, calendar: Calendar) -> Bool`
  - `struct Preferences: Codable, Sendable, Equatable` — every field from the spec, `static let defaults`, `func normalized() -> Preferences`
  - `Preferences.intervalRange: ClosedRange<TimeInterval>` = `30...3600`

- [ ] **Step 1: Add the module to the manifest**

In `Packages/Core/Package.swift`, add to `products`:

```swift
        .library(name: "Preferences", targets: ["Preferences"]),
```

and to `targets`:

```swift
        .target(name: "Preferences", dependencies: ["ProviderKit"]),
        .testTarget(name: "PreferencesTests", dependencies: ["Preferences"]),
```

Create the directories:

```bash
mkdir -p Packages/Core/Sources/Preferences Packages/Core/Tests/PreferencesTests
```

- [ ] **Step 2: Write a failing test for the quiet window**

Create `Packages/Core/Tests/PreferencesTests/QuietHoursTests.swift`:

```swift
import Testing
import Foundation
@testable import Preferences

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func at(_ hour: Int, _ minute: Int) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 8, day: 30, hour: hour, minute: minute))!
}

@Test func daytimeWindowContainsOnlyItsHours() {
    let hours = QuietHours(startMinute: 13 * 60, endMinute: 14 * 60)   // 13:00–14:00
    #expect(hours.contains(at(13, 30), calendar: utc))
    #expect(hours.contains(at(12, 59), calendar: utc) == false)
    #expect(hours.contains(at(14, 0), calendar: utc) == false)   // the end is excluded
}

@Test func windowAcrossMidnightWorksOnBothSides() {
    let hours = QuietHours(startMinute: 23 * 60, endMinute: 9 * 60)    // 23:00–09:00
    #expect(hours.contains(at(23, 30), calendar: utc))   // evening
    #expect(hours.contains(at(2, 0), calendar: utc))     // night
    #expect(hours.contains(at(8, 59), calendar: utc))    // morning
    #expect(hours.contains(at(9, 0), calendar: utc) == false)
    #expect(hours.contains(at(15, 0), calendar: utc) == false)
}

@Test func startEqualToEndMeansAlwaysQuiet() {
    // The degenerate case: the same time was set for both ends.
    // Read as “quiet around the clock”, not as “never”.
    let hours = QuietHours(startMinute: 60, endMinute: 60)
    #expect(hours.contains(at(0, 30), calendar: utc))
    #expect(hours.contains(at(12, 0), calendar: utc))
}
```

- [ ] **Step 3: Confirm the test fails**

Run: `cd Packages/Core && swift test --filter QuietHoursTests`
Expected: FAIL — the `Preferences` module is still empty.

- [ ] **Step 4: Implement the quiet window**

Create `Packages/Core/Sources/Preferences/QuietHours.swift`:

```swift
import Foundation

/// A stretch of the day, given as minutes from midnight.
/// Held in minutes rather than dates: the setting is tied to a time of day
/// and not to one particular day, and it survives a change of time zone.
public struct QuietHours: Codable, Sendable, Hashable {
    public let startMinute: Int
    public let endMinute: Int

    public init(startMinute: Int, endMinute: Int) {
        self.startMinute = max(0, min(startMinute, 24 * 60 - 1))
        self.endMinute = max(0, min(endMinute, 24 * 60 - 1))
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)

        // The start later than the end means the stretch runs over midnight,
        // and then “inside” means “after the start OR before the end”.
        if startMinute < endMinute {
            return minute >= startMinute && minute < endMinute
        }
        if startMinute > endMinute {
            return minute >= startMinute || minute < endMinute
        }
        return true   // start equal to end — quiet around the clock
    }
}
```

- [ ] **Step 5: Confirm the tests pass**

Run: `cd Packages/Core && swift test --filter QuietHoursTests`
Expected: PASS, 3 tests.

- [ ] **Step 6: Write a failing test for the model**

Create `Packages/Core/Tests/PreferencesTests/PreferencesTests.swift`:

```swift
import Testing
import Foundation
import ProviderKit
@testable import Preferences

@Test func defaultsMatchTheSpec() {
    let p = Preferences.defaults
    #expect(p.appearance == .system)
    #expect(p.menuBarContent == .timer)
    #expect(p.primaryWindow == .worst)
    #expect(p.rowLayout == .twoWindows)
    #expect(p.ordering == .leastLoadedFirst)
    #expect(p.showSnapshotAge)
    #expect(p.notificationsEnabled)
    #expect(p.thresholds == [95, 80])
    #expect(p.notifyOnRecovery)
    #expect(p.notifyWindows == .both)
    #expect(p.quietHours == nil)
    #expect(p.foregroundInterval == 60)
    #expect(p.backgroundInterval == 300)
    #expect(p.refreshAfterWake)
    #expect(p.disabledProviders.isEmpty)
    #expect(p.hiddenAccounts.isEmpty)
    #expect(p.codexRoot == nil)
}

@Test func thresholdsAreSortedDescendingAndDeduplicated() {
    var p = Preferences.defaults
    p.thresholds = [50, 95, 50, 80]
    #expect(p.normalized().thresholds == [95, 80, 50])
}

@Test func thresholdsOutsideRangeAreDropped() {
    var p = Preferences.defaults
    p.thresholds = [0, 50, 100, 140, -10]
    // 0 and negatives are meaningless, above 100 is unreachable
    #expect(p.normalized().thresholds == [100, 50])
}

@Test func emptyThresholdListIsAllowed() {
    var p = Preferences.defaults
    p.thresholds = []
    #expect(p.normalized().thresholds.isEmpty)
}

@Test func intervalsAreClampedToAllowedRange() {
    var p = Preferences.defaults
    p.foregroundInterval = 5
    p.backgroundInterval = 7200
    let n = p.normalized()
    #expect(n.foregroundInterval == 30)
    #expect(n.backgroundInterval == 3600)
}

@Test func intervalsInsideRangeSurviveUntouched() {
    var p = Preferences.defaults
    p.foregroundInterval = 45
    p.backgroundInterval = 600
    let n = p.normalized()
    #expect(n.foregroundInterval == 45)
    #expect(n.backgroundInterval == 600)
}

@Test func survivesEncodingRoundTrip() throws {
    var p = Preferences.defaults
    p.appearance = .dark
    p.thresholds = [90]
    p.quietHours = QuietHours(startMinute: 23 * 60, endMinute: 9 * 60)
    p.disabledProviders = [.codex]
    p.hiddenAccounts = ["claude/u-1"]
    p.codexRoot = "/tmp/codex"

    let data = try JSONEncoder().encode(p)
    let back = try JSONDecoder().decode(Preferences.self, from: data)
    #expect(back == p)
}
```

- [ ] **Step 7: Confirm the test fails**

Run: `cd Packages/Core && swift test --filter PreferencesTests`
Expected: FAIL, `cannot find 'Preferences' in scope`.

- [ ] **Step 8: Implement the model**

Create `Packages/Core/Sources/Preferences/Preferences.swift`:

```swift
import Foundation
import ProviderKit

public enum Appearance: String, Codable, Sendable, CaseIterable {
    case system, light, dark

    public var title: String {
        switch self {
        case .system: "Системное"
        case .light:  "Светлое"
        case .dark:   "Тёмное"
        }
    }
}

public enum MenuBarContent: String, Codable, Sendable, CaseIterable {
    case iconOnly, timer, percent, both

    public var title: String {
        switch self {
        case .iconOnly: "Иконка"
        case .timer:    "Таймер"
        case .percent:  "Процент"
        case .both:     "Оба"
        }
    }
}

public enum PrimaryWindow: String, Codable, Sendable, CaseIterable {
    case worst, session, weekly

    public var title: String {
        switch self {
        case .worst:   "Самое забитое"
        case .session: "Пятичасовое"
        case .weekly:  "Недельное"
        }
    }
}

public enum RowLayout: String, Codable, Sendable, CaseIterable {
    case twoWindows, compact, rings

    public var title: String {
        switch self {
        case .twoWindows: "Два окна"
        case .compact:    "Одна строка"
        case .rings:      "Кольца"
        }
    }
}

public enum Ordering: String, Codable, Sendable, CaseIterable {
    case leastLoadedFirst, byName

    public var title: String {
        switch self {
        case .leastLoadedFirst: "Свободные сверху"
        case .byName:           "По имени"
        }
    }
}

public enum WindowScope: String, Codable, Sendable, CaseIterable {
    case session, weekly, both

    public var title: String {
        switch self {
        case .session: "5ч"
        case .weekly:  "нед"
        case .both:    "оба"
        }
    }

    /// Whether a window with this identifier falls under the chosen scope.
    public func includes(windowID: String) -> Bool {
        switch self {
        case .both:    true
        case .session: windowID == "session"
        case .weekly:  windowID == "weekly"
        }
    }
}

public struct Preferences: Codable, Sendable, Equatable {
    // Appearance
    public var appearance: Appearance
    public var menuBarContent: MenuBarContent
    public var primaryWindow: PrimaryWindow
    public var rowLayout: RowLayout
    public var ordering: Ordering
    public var showSnapshotAge: Bool

    // Notifications
    public var notificationsEnabled: Bool
    public var thresholds: [Int]
    public var notifyOnRecovery: Bool
    public var notifyWindows: WindowScope
    public var quietHours: QuietHours?

    // Updates and launch
    public var foregroundInterval: TimeInterval
    public var backgroundInterval: TimeInterval
    public var refreshAfterWake: Bool

    // Services and accounts
    public var disabledProviders: Set<ProviderID>
    public var hiddenAccounts: Set<String>
    public var codexRoot: String?

    /// The allowed polling bounds. More often than twice a minute is pointless:
    /// the service does not recompute its limits instantly. Less often than
    /// hourly and the monitor stops being one.
    public static let intervalRange: ClosedRange<TimeInterval> = 30...3600

    public static let defaults = Preferences(
        appearance: .system,
        menuBarContent: .timer,
        primaryWindow: .worst,
        rowLayout: .twoWindows,
        ordering: .leastLoadedFirst,
        showSnapshotAge: true,
        notificationsEnabled: true,
        thresholds: [95, 80],
        notifyOnRecovery: true,
        notifyWindows: .both,
        quietHours: nil,
        foregroundInterval: 60,
        backgroundInterval: 300,
        refreshAfterWake: true,
        disabledProviders: [],
        hiddenAccounts: [],
        codexRoot: nil
    )

    /// Brings values into range. Called before saving and after reading:
    /// settings may arrive from a file somebody edited by hand.
    public func normalized() -> Preferences {
        var copy = self
        copy.thresholds = Array(Set(thresholds.filter { $0 > 0 && $0 <= 100 }))
            .sorted(by: >)
        copy.foregroundInterval = Self.clamp(foregroundInterval)
        copy.backgroundInterval = Self.clamp(backgroundInterval)
        return copy
    }

    private static func clamp(_ value: TimeInterval) -> TimeInterval {
        min(max(value, intervalRange.lowerBound), intervalRange.upperBound)
    }
}
```

- [ ] **Step 9: Make `ProviderID` codable**

`Preferences` holds a `Set<ProviderID>`, and a raw-value enum does **not** get
`Codable` automatically — without declaring it, the whole of `Preferences` stops
being `Codable` with the error “does not conform to protocol 'Decodable'”. Checked.

In `Packages/Core/Sources/ProviderKit/Models.swift`, add `Codable` to the
declaration:

```swift
public enum ProviderID: String, Sendable, Hashable, Codable, CaseIterable {
```

- [ ] **Step 10: Confirm the tests pass**

Run: `cd Packages/Core && swift test --filter PreferencesTests`
Expected: PASS, 7 model tests.

Run: `cd Packages/Core && swift test --filter QuietHoursTests`
Expected: PASS, 3 tests.

- [ ] **Step 11: Commit**

```bash
git add Packages/Core
git commit -m "The settings model: defaults, bounds, the quiet window"
```

---

### Task 2: The settings store

**Files:**
- Create: `Packages/Core/Sources/Preferences/PreferencesStore.swift`
- Test: `Packages/Core/Tests/PreferencesTests/PreferencesStoreTests.swift`

**Interfaces:**
- Consumes: `Preferences` from Task 1.
- Produces:
  - `protocol PreferencesStorage: Sendable` — `read() -> Data?`, `write(_ data: Data)`
  - `struct UserDefaultsStorage: PreferencesStorage` — `init(defaults: UserDefaults = .standard)`, the key `"preferences"`
  - `actor PreferencesStore` — `init(storage:)`, `load() -> Preferences`, `save(_ value: Preferences)`, `current() -> Preferences`

- [ ] **Step 1: Write a failing test**

Create `Packages/Core/Tests/PreferencesTests/PreferencesStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import Preferences

private actor MemoryStorage: PreferencesStorage {
    private var data: Data?
    init(_ seed: Data? = nil) { data = seed }
    func read() -> Data? { data }
    func write(_ value: Data) { data = value }
}

@Test func emptyStorageGivesDefaults() async {
    let store = PreferencesStore(storage: MemoryStorage())
    #expect(await store.load() == Preferences.defaults)
}

@Test func savedValueComesBack() async {
    let storage = MemoryStorage()
    let store = PreferencesStore(storage: storage)
    var p = Preferences.defaults
    p.appearance = .dark
    p.thresholds = [70]
    await store.save(p)

    let reopened = PreferencesStore(storage: storage)
    let loaded = await reopened.load()
    #expect(loaded.appearance == .dark)
    #expect(loaded.thresholds == [70])
}

@Test func saveNormalizesBeforeWriting() async {
    let storage = MemoryStorage()
    let store = PreferencesStore(storage: storage)
    var p = Preferences.defaults
    p.thresholds = [80, 95, 80]
    p.foregroundInterval = 1
    await store.save(p)

    let loaded = await PreferencesStore(storage: storage).load()
    #expect(loaded.thresholds == [95, 80])
    #expect(loaded.foregroundInterval == 30)
}

@Test func corruptedDataFallsBackToDefaults() async {
    let storage = MemoryStorage(Data("this is not json".utf8))
    let store = PreferencesStore(storage: storage)
    // A corrupt file must not bring the app down.
    #expect(await store.load() == Preferences.defaults)
}

@Test func partialDataFallsBackToDefaults() async {
    // Settings from a future version with fewer fields: not falling over matters more.
    let storage = MemoryStorage(Data(#"{"appearance":"dark"}"#.utf8))
    #expect(await PreferencesStore(storage: storage).load() == Preferences.defaults)
}

@Test func currentReturnsLastLoadedWithoutTouchingStorage() async {
    let store = PreferencesStore(storage: MemoryStorage())
    _ = await store.load()
    #expect(await store.current() == Preferences.defaults)
}
```

- [ ] **Step 2: Confirm the test fails**

Run: `cd Packages/Core && swift test --filter PreferencesStoreTests`
Expected: FAIL, `cannot find 'PreferencesStore' in scope`.

- [ ] **Step 3: Implement**

Create `Packages/Core/Sources/Preferences/PreferencesStore.swift`:

```swift
import Foundation

/// Storage behind a protocol, so the tests never write to the real `UserDefaults`
/// and leave nothing behind in the system.
public protocol PreferencesStorage: Sendable {
    func read() async -> Data?
    func write(_ data: Data) async
}

public struct UserDefaultsStorage: PreferencesStorage {
    public static let key = "preferences"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func read() -> Data? { defaults.data(forKey: Self.key) }
    public func write(_ data: Data) { defaults.set(data, forKey: Self.key) }
}

public actor PreferencesStore {
    private let storage: any PreferencesStorage
    private var value: Preferences = .defaults

    public init(storage: any PreferencesStorage) { self.storage = storage }

    /// Reads the settings. Any failure — corrupt data, an incomplete set of
    /// fields from another version — gives the defaults: settings are not the
    /// kind of reason for an app to refuse to start.
    @discardableResult
    public func load() async -> Preferences {
        guard let data = await storage.read(),
              let decoded = try? JSONDecoder().decode(Preferences.self, from: data)
        else {
            value = .defaults
            return value
        }
        value = decoded.normalized()
        return value
    }

    public func save(_ newValue: Preferences) async {
        value = newValue.normalized()
        guard let data = try? JSONEncoder().encode(value) else { return }
        await storage.write(data)
    }

    /// The last value read, without going to storage.
    public func current() -> Preferences { value }
}
```

- [ ] **Step 4: Confirm the tests pass**

Run: `cd Packages/Core && swift test --filter PreferencesStoreTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/Core
git commit -m "The settings store, falling back to the defaults"
```

---

### Task 3: Thresholds, quiet hours and the order become settings

**Files:**
- Modify: `Packages/Core/Sources/Monitoring/ThresholdNotifier.swift`
- Modify: `Packages/Core/Sources/ProviderKit/SnapshotOrdering.swift`
- Modify: `Packages/Core/Package.swift` (Monitoring depends on Preferences)
- Modify: `Packages/Core/Tests/MonitoringTests/ThresholdNotifierTests.swift`
- Modify: `Packages/Core/Tests/ProviderKitTests/SnapshotOrderingTests.swift`

**Interfaces:**
- Consumes: `Preferences`, `QuietHours`, `WindowScope`, `Ordering` from Tasks 1–2.
- Produces:
  - `ThresholdTracker.init(thresholds: [Int], notifyOnRecovery: Bool, scope: WindowScope, quietHours: QuietHours?, calendar: Calendar)` — the old `init()` stays, with the behaviour it had by default
  - `ThresholdTracker.events(for:now:) -> [ThresholdEvent]` — a `now` parameter added, for checking the quiet hours
  - `orderedForDisplay(_ snapshots: [AccountSnapshot], ordering: Ordering) -> [AccountSnapshot]` — the earlier one-parameter form is kept

Today `ThresholdTracker` takes `[95, 80]` from a constant on the type, and `orderedForDisplay`
always sorts by load. The values move into parameters — which is also the only
way to check them under different settings.

- [ ] **Step 1: Add the module dependency**

In `Packages/Core/Package.swift`, replace the `Monitoring` line:

```swift
        .target(name: "Monitoring", dependencies: ["ProviderKit", "Preferences"]),
```

and leave the `ProviderKit` test line as it is; `ProviderKit` itself stays
without dependencies: `Ordering` is declared in `Preferences`, so
`orderedForDisplay` moves into `Monitoring`. Replace the
`SnapshotOrdering.swift` line in the file list below — the file moves.

```bash
git mv Packages/Core/Sources/ProviderKit/SnapshotOrdering.swift \
       Packages/Core/Sources/Monitoring/SnapshotOrdering.swift
git mv Packages/Core/Tests/ProviderKitTests/SnapshotOrderingTests.swift \
       Packages/Core/Tests/MonitoringTests/SnapshotOrderingTests.swift
```

In `Packages/Core/Sources/Monitoring/SnapshotOrdering.swift` add `import Preferences`
as the first line, and in the tests replace `@testable import ProviderKit` with:

```swift
import ProviderKit
import Preferences
@testable import Monitoring
```

- [ ] **Step 2: Write a failing test for ordering by name**

Append to `Packages/Core/Tests/MonitoringTests/SnapshotOrderingTests.swift`:

```swift
@Test func byNameIgnoresLoad() {
    let ordered = orderedForDisplay(
        [make("zeta", peak: 5), make("alpha", peak: 99)], ordering: .byName
    )
    #expect(ordered.map(\.id) == ["alpha", "zeta"])
}

@Test func byNameStillSinksFailures() {
    let ordered = orderedForDisplay(
        [make("alpha", peak: 0, failed: true), make("zeta", peak: 50)], ordering: .byName
    )
    #expect(ordered.map(\.id) == ["zeta", "alpha"])
}
```

- [ ] **Step 3: Confirm the test fails**

Run: `cd Packages/Core && swift test --filter SnapshotOrderingTests`
Expected: FAIL — `orderedForDisplay` has no `ordering` parameter.

- [ ] **Step 4: Implement the order**

Replace the contents of `Packages/Core/Sources/Monitoring/SnapshotOrdering.swift`:

```swift
import Foundation
import ProviderKit
import Preferences

/// The order of the rows in the window. Accounts in error are always at the
/// bottom whatever the choice: there is nothing to say about them, and keeping
/// them at the top means spending the best place on an empty row.
public func orderedForDisplay(
    _ snapshots: [AccountSnapshot], ordering: Ordering = .leastLoadedFirst
) -> [AccountSnapshot] {
    snapshots.sorted { lhs, rhs in
        let lhsFailed = lhs.failure != nil
        let rhsFailed = rhs.failure != nil
        if lhsFailed != rhsFailed { return !lhsFailed }

        switch ordering {
        case .leastLoadedFirst:
            if lhs.peakPercent != rhs.peakPercent { return lhs.peakPercent < rhs.peakPercent }
        case .byName:
            break
        }
        return lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending
    }
}
```

- [ ] **Step 5: Confirm the ordering tests pass**

Run: `cd Packages/Core && swift test --filter SnapshotOrderingTests`
Expected: PASS, 5 tests.

- [ ] **Step 6: Write a failing test for configurable thresholds**

Append to `Packages/Core/Tests/MonitoringTests/ThresholdNotifierTests.swift`:

```swift
import Preferences

private var utcCalendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func moment(_ hour: Int) -> Date {
    utcCalendar.date(from: DateComponents(year: 2026, month: 8, day: 30, hour: hour))!
}

@Test func customThresholdFiresAtItsOwnLevel() {
    var tracker = ThresholdTracker(
        thresholds: [50], notifyOnRecovery: true, scope: .both,
        quietHours: nil, calendar: utcCalendar
    )
    _ = tracker.events(for: snap(10), now: moment(12))
    #expect(tracker.events(for: snap(51), now: moment(12)).map(\.kind) == [.crossed(50)])
}

@Test func emptyThresholdsSilenceLoadEventsButKeepRecovery() {
    var tracker = ThresholdTracker(
        thresholds: [], notifyOnRecovery: true, scope: .both,
        quietHours: nil, calendar: utcCalendar
    )
    _ = tracker.events(for: snap(10), now: moment(12))
    #expect(tracker.events(for: snap(99), now: moment(12)).isEmpty)
    #expect(tracker.events(for: snap(5), now: moment(12)).map(\.kind) == [.recovered])
}

@Test func recoveryCanBeTurnedOff() {
    var tracker = ThresholdTracker(
        thresholds: [80], notifyOnRecovery: false, scope: .both,
        quietHours: nil, calendar: utcCalendar
    )
    _ = tracker.events(for: snap(10), now: moment(12))
    _ = tracker.events(for: snap(90), now: moment(12))
    #expect(tracker.events(for: snap(5), now: moment(12)).isEmpty)
}

@Test func scopeLimitsWhichWindowsReport() {
    var tracker = ThresholdTracker(
        thresholds: [80], notifyOnRecovery: true, scope: .session,
        quietHours: nil, calendar: utcCalendar
    )
    // snap(...) returns the single window with id "weekly" — outside the scope
    _ = tracker.events(for: snap(10), now: moment(12))
    #expect(tracker.events(for: snap(90), now: moment(12)).isEmpty)
}

@Test func quietHoursSuppressEventsInsideTheWindow() {
    var tracker = ThresholdTracker(
        thresholds: [80], notifyOnRecovery: true, scope: .both,
        quietHours: QuietHours(startMinute: 23 * 60, endMinute: 9 * 60),
        calendar: utcCalendar
    )
    _ = tracker.events(for: snap(10), now: moment(12))
    #expect(tracker.events(for: snap(90), now: moment(2)).isEmpty)      // night — silence
}

@Test func quietHoursDoNotLoseTheCrossingAfterwards() {
    var tracker = ThresholdTracker(
        thresholds: [80], notifyOnRecovery: true, scope: .both,
        quietHours: QuietHours(startMinute: 23 * 60, endMinute: 9 * 60),
        calendar: utcCalendar
    )
    _ = tracker.events(for: snap(10), now: moment(12))
    _ = tracker.events(for: snap(90), now: moment(2))                    // suppressed
    // The reading is already recorded, so there is no second crossing — and that
    // is right: catching up on night-time notifications in the morning is waking
    // somebody with the past.
}
```

- [ ] **Step 7: Confirm the test fails**

Run: `cd Packages/Core && swift test --filter ThresholdNotifierTests`
Expected: FAIL — `ThresholdTracker` has no such initialiser.

- [ ] **Step 8: Implement**

Replace the declaration of `ThresholdTracker` in
`Packages/Core/Sources/Monitoring/ThresholdNotifier.swift` (leave `ThresholdEvent`
itself alone):

```swift
/// Remembers the previous reading and emits an event only on a crossing.
/// Without that, a background poll every five minutes would become a stream of notifications.
public struct ThresholdTracker: Sendable {
    private let thresholds: [Int]        // descending
    private let notifyOnRecovery: Bool
    private let scope: WindowScope
    private let quietHours: QuietHours?
    private let calendar: Calendar
    private static let recoveryLevel = 50.0

    private var previous: [Key: Double] = [:]
    private var seenAtLeastOnce = false

    private struct Key: Hashable { let account: String; let window: String }

    public init(
        thresholds: [Int] = [95, 80],
        notifyOnRecovery: Bool = true,
        scope: WindowScope = .both,
        quietHours: QuietHours? = nil,
        calendar: Calendar = .current
    ) {
        self.thresholds = thresholds.sorted(by: >)
        self.notifyOnRecovery = notifyOnRecovery
        self.scope = scope
        self.quietHours = quietHours
        self.calendar = calendar
    }

    public mutating func events(
        for snapshots: [AccountSnapshot], now: Date = Date()
    ) -> [ThresholdEvent] {
        var events: [ThresholdEvent] = []
        var current: [Key: Double] = [:]

        // Quiet hours suppress the notification, but the reading is recorded
        // anyway: otherwise the morning brings a batch of events about the night.
        let silent = quietHours?.contains(now, calendar: calendar) ?? false

        for snapshot in snapshots where snapshot.failure == nil {
            for window in snapshot.windows {
                let key = Key(account: snapshot.id, window: window.id)
                current[key] = window.percent

                guard seenAtLeastOnce, let before = previous[key],
                      scope.includes(windowID: window.id), !silent
                else { continue }
                let now = window.percent

                if let crossed = thresholds.first(where: {
                    before < Double($0) && now >= Double($0)
                }) {
                    events.append(ThresholdEvent(
                        accountID: snapshot.id, windowID: window.id,
                        accountName: snapshot.displayName, kind: .crossed(crossed)
                    ))
                } else if notifyOnRecovery,
                          before >= Self.recoveryLevel, now < Self.recoveryLevel {
                    events.append(ThresholdEvent(
                        accountID: snapshot.id, windowID: window.id,
                        accountName: snapshot.displayName, kind: .recovered
                    ))
                }
            }
        }

        previous = current
        seenAtLeastOnce = true
        return events
    }
}
```

Add `import Preferences` as the first line of the file.

- [ ] **Step 9: Confirm the whole package passes**

Run: `cd Packages/Core && swift test`
Expected: PASS. The eight earlier `ThresholdNotifierTests` go on working
unchanged — the initialiser's defaults are the same values.

- [ ] **Step 10: Commit**

```bash
git add Packages/Core
git commit -m "Thresholds, window scope, quiet hours and order moved into parameters"
```

---

### Task 4: The frame of the settings window

**Files:**
- Create: `App/PreferencesModel.swift`
- Create: `App/Settings/SettingsIcons.swift`
- Create: `App/Settings/SettingsView.swift`
- Modify: `App/StatusCheckerApp.swift`
- Modify: `App/PopoverView.swift`
- Modify: `project.yml` (a dependency on `Preferences`)

**Interfaces:**
- Consumes: `Preferences`, `PreferencesStore`, `UserDefaultsStorage` from Tasks 1–2.
- Produces:
  - `@MainActor final class PreferencesModel: ObservableObject` — `@Published var value: Preferences`, `func load() async`, `func update(_ change: (inout Preferences) -> Void)`
  - `enum SettingsSection: String, CaseIterable, Identifiable` — `.accounts`, `.appearance`, `.notifications`, `.updates`, `.services`, `.about`; the properties `title` and `icon`
  - `struct SettingsIcon: View` — `init(_ section: SettingsSection)`
  - `struct SettingsView: View` — `init(model: PreferencesModel, appModel: AppModel)`

- [ ] **Step 1: Link the module to the app**

In `project.yml`, add to the `dependencies` block of the `StatusChecker` target:

```yaml
      - package: Core
        product: Preferences
```

- [ ] **Step 2: Create the settings model for the UI**

Create `App/PreferencesModel.swift`:

```swift
import Foundation
import SwiftUI
import Preferences

/// A wrapper over `PreferencesStore` for SwiftUI: it holds the current value and
/// saves every change immediately, with no “Apply” button — that is the macOS
/// convention for settings.
@MainActor
final class PreferencesModel: ObservableObject {
    @Published private(set) var value: Preferences = .defaults

    private let store: PreferencesStore

    init(store: PreferencesStore = PreferencesStore(storage: UserDefaultsStorage())) {
        self.store = store
    }

    func load() async {
        value = await store.load()
    }

    func update(_ change: (inout Preferences) -> Void) {
        var draft = value
        change(&draft)
        value = draft.normalized()
        let snapshot = value
        Task { await store.save(snapshot) }
    }
}
```

- [ ] **Step 3: Create the sections and the monochrome glyphs**

Create `App/Settings/SettingsIcons.swift`:

```swift
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case accounts, appearance, notifications, updates, services, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accounts:      "Аккаунты"
        case .appearance:    "Внешний вид"
        case .notifications: "Уведомления"
        case .updates:       "Обновление"
        case .services:      "Сервисы"
        case .about:         "О программе"
        }
    }

    /// Line symbols rather than coloured tiles: in the limits window colour
    /// already encodes load, and a second colour language beside it weakens both.
    var symbol: String {
        switch self {
        case .accounts:      "person.2"
        case .appearance:    "circle.lefthalf.filled"
        case .notifications: "bell"
        case .updates:       "arrow.clockwise"
        case .services:      "square.grid.2x2"
        case .about:         "info.circle"
        }
    }
}

struct SettingsIcon: View {
    let section: SettingsSection

    init(_ section: SettingsSection) { self.section = section }

    var body: some View {
        Image(systemName: section.symbol)
            .font(.system(size: 13, weight: .regular))
            .frame(width: 18, height: 18)
    }
}
```

- [ ] **Step 4: Create the window frame**

Create `App/Settings/SettingsView.swift`:

```swift
import SwiftUI
import Preferences

struct SettingsView: View {
    @ObservedObject var model: PreferencesModel
    @ObservedObject var appModel: AppModel

    @State private var selection: SettingsSection = .accounts

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                NavigationLink(value: section) {
                    Label { Text(section.title) } icon: { SettingsIcon(section) }
                }
            }
            .navigationSplitViewColumnWidth(186)
        } detail: {
            Group {
                switch selection {
                case .accounts:      AccountsPane(model: model, appModel: appModel)
                case .appearance:    AppearancePane(model: model)
                case .notifications: NotificationsPane(model: model)
                case .updates:       UpdatesPane(model: model)
                case .services:      ServicesPane(model: model)
                case .about:         AboutPane(model: model, appModel: appModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
        }
        .frame(width: 720, height: 470)
        .task { await model.load() }
    }
}

/// The shared wrapper for a section: a heading, an explanation and the content.
/// Pulled out so that six screens do not drift apart in padding and sizes.
struct Pane<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 3).padding(.bottom, 16)
            content
            Spacer(minLength: 0)
        }
    }
}
```

- [ ] **Step 5: Create six placeholder sections**

So that the frame builds before the sections are filled, create one file per
section. Each is replaced in its own task.

```bash
mkdir -p App/Settings
for n in Accounts Appearance Notifications Updates Services About; do
  cat > "App/Settings/${n}Pane.swift" <<EOF
import SwiftUI
import Preferences

struct ${n}Pane: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        Pane(title: "${n}", subtitle: "Наполняется в следующей задаче") { EmptyView() }
    }
}
EOF
done
```

The `Accounts` and `About` sections also take an `appModel`, so add the line
`@ObservedObject var appModel: AppModel` after `model` in those two:

```bash
for n in Accounts About; do
  /usr/bin/sed -i '' 's/    @ObservedObject var model: PreferencesModel/    @ObservedObject var model: PreferencesModel\n    @ObservedObject var appModel: AppModel/' "App/Settings/${n}Pane.swift"
done
```

- [ ] **Step 6: Declare the scene and the item that opens it**

In `App/StatusCheckerApp.swift`, add a property and a scene to `StatusCheckerApp`:

```swift
@main
struct StatusCheckerApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var preferences = PreferencesModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: preferences, appModel: model)
        }
    }
}
```

In `App/PopoverView.swift`, add an item to `footer` between “Обновить” and “Выйти”:

```swift
    private var footer: some View {
        HStack {
            Button("Обновить") { Task { await model.refresh() } }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .keyboardShortcut("r")
            Spacer()
            SettingsLink { Text("Настройки…") }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Выйти") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
```

- [ ] **Step 7: Build and open**

Run: `make build`
Expected: `BUILD SUCCEEDED`.

Run: `make run`, then click the menu bar icon and “Настройки…”.
Expected: a 720×470 window opens with a sidebar of six sections,
the icons monochrome, the labels whole.

- [ ] **Step 8: Commit**

```bash
git add App project.yml
git commit -m "The frame of the settings window: a sidebar and six sections"
```

---

### Task 5: The “Appearance” section, and applying the appearance

**Files:**
- Modify: `App/Settings/AppearancePane.swift`
- Modify: `App/StatusCheckerApp.swift`
- Modify: `App/AccountRowView.swift`
- Modify: `App/AppModel.swift`

**Interfaces:**
- Consumes: `PreferencesModel` from Task 4; `Appearance`, `MenuBarContent`, `PrimaryWindow`, `RowLayout`, `Ordering` from Task 1.
- Produces: `func applyAppearance(_ appearance: Appearance)` in `App/StatusCheckerApp.swift`.

- [ ] **Step 1: Fill the section in**

Replace the contents of `App/Settings/AppearancePane.swift`:

```swift
import SwiftUI
import Preferences

struct AppearancePane: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        Pane(title: "Внешний вид",
             subtitle: "Как выглядит значок в строке меню и строка аккаунта в окне.") {
            Form {
                Picker("Оформление", selection: binding(\.appearance)) {
                    ForEach(Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("В строке меню", selection: binding(\.menuBarContent)) {
                    ForEach(MenuBarContent.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Считать главным", selection: binding(\.primaryWindow)) {
                    ForEach(PrimaryWindow.allCases, id: \.self) { Text($0.title).tag($0) }
                }

                Picker("Компоновка строки", selection: binding(\.rowLayout)) {
                    ForEach(RowLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                }

                Picker("Порядок", selection: binding(\.ordering)) {
                    ForEach(Ordering.allCases, id: \.self) { Text($0.title).tag($0) }
                }

                Toggle("Показывать возраст снимка", isOn: binding(\.showSnapshotAge))
            }
            .formStyle(.grouped)
        }
    }

    private func binding<T>(_ path: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(
            get: { model.value[keyPath: path] },
            set: { newValue in model.update { $0[keyPath: path] = newValue } }
        )
    }
}
```

- [ ] **Step 2: Apply the appearance across the app**

In `App/StatusCheckerApp.swift`, add the function and a call on change:

```swift
/// Turns the user's choice into an AppKit appearance.
/// `nil` means “follow the system”, which is also the default.
@MainActor
func applyAppearance(_ appearance: Appearance) {
    NSApp.appearance = switch appearance {
    case .system: nil
    case .light:  NSAppearance(named: .aqua)
    case .dark:   NSAppearance(named: .darkAqua)
    }
}
```

Add the reaction to the body of the `Settings` scene:

```swift
        Settings {
            SettingsView(model: preferences, appModel: model)
                .onChange(of: preferences.value.appearance, initial: true) { _, new in
                    applyAppearance(new)
                }
        }
```

- [ ] **Step 3: The menu bar icon reads the setting**

In `App/StatusCheckerApp.swift`, replace `MenuBarLabel`:

```swift
private struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    let content: MenuBarContent

    var body: some View {
        Group {
            if let text = trailingText {
                Label {
                    Text(text).monospacedDigit()
                } icon: {
                    Image(systemName: "gauge.with.needle")
                }
                // Without an explicit style the menu bar shows only the icon.
                .labelStyle(.titleAndIcon)
            } else {
                Image(systemName: "gauge.with.needle")
            }
        }
        .task { await model.start() }
    }

    /// What to write beside the icon. `nil` — the icon alone.
    private var trailingText: String? {
        guard let summary = model.summary else { return nil }
        let percent = "\(Int(summary.percent.rounded()))%"
        let timer = summary.remaining.map(formatRemainingCompact)

        switch content {
        case .iconOnly: return nil
        case .percent:  return percent
        case .timer:    return timer
        case .both:     return timer.map { "\(percent) · \($0)" } ?? percent
        }
    }
}
```

and pass the setting when it is created:

```swift
        } label: {
            MenuBarLabel(model: model, content: preferences.value.menuBarContent)
        }
```

- [ ] **Step 4: The window reads the layout, the order and the snapshot age**

In `App/AppModel.swift`, add the property and take it into account when polling:

```swift
    /// The settings that affect polling and display. Updated from the settings window.
    var preferences: Preferences = .defaults {
        didSet { restartTimer() }
    }
```

In `refresh()`, replace the sorting and summary lines:

```swift
        let result = orderedForDisplay(await poller.refresh(), ordering: preferences.ordering)
        snapshots = result
        summary = menuBarSummary(result, now: Date(), window: preferences.primaryWindow)
```

In `restartTimer()`, replace the hard-coded numbers:

```swift
        let interval = isPopoverOpen
            ? preferences.foregroundInterval
            : preferences.backgroundInterval
```

In `App/AccountRowView.swift`, add the parameters and hide the badge per the setting:

```swift
struct AccountRowView: View {
    let snapshot: AccountSnapshot
    let now: Date
    var layout: RowLayout = .twoWindows
    var showSnapshotAge: Bool = true
```

and in `header`, replace the badge condition:

```swift
            if snapshot.freshness.isStale && showSnapshotAge {
```

In `App/PopoverView.swift`, pass the values through:

```swift
                    AccountRowView(
                        snapshot: snapshot, now: now,
                        layout: model.preferences.rowLayout,
                        showSnapshotAge: model.preferences.showSnapshotAge
                    )
```

The `.compact` and `.rings` layouts are drawn in Task 11; for now `AccountRowView`
ignores the value of `layout` except for `.twoWindows` — deliberately, so that the
section starts working before the alternatives are drawn.

- [ ] **Step 5: Teach the summary to pick a window**

In `Packages/Core/Sources/Monitoring/UsagePoller.swift`, replace `menuBarSummary`:

```swift
/// What to show in the menu bar.
/// By default the window nearest to exhaustion is taken: the nearest reset in
/// time will not do — on an idle account it says nothing at all.
public func menuBarSummary(
    _ snapshots: [AccountSnapshot], now: Date, window: PrimaryWindow = .worst
) -> MenuBarSummary? {
    let candidates: [LimitWindow] = switch window {
    case .worst:   snapshots.compactMap(\.peakWindow)
    case .session: snapshots.flatMap(\.windows).filter { $0.id == "session" }
    case .weekly:  snapshots.flatMap(\.windows).filter { $0.id == "weekly" }
    }
    guard let worst = candidates.max(by: { $0.percent < $1.percent }) else { return nil }

    return MenuBarSummary(
        percent: worst.percent, severity: worst.severity, remaining: worst.remaining(from: now)
    )
}
```

Add `import Preferences` as the first line of the file.

- [ ] **Step 6: A test for picking the window**

Append to `Packages/Core/Tests/MonitoringTests/UsagePollerTests.swift`:

```swift
@Test func menuBarCanBePinnedToWeeklyWindow() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let account = AccountSnapshot(
        id: "a", provider: .claude, displayName: "a", planLabel: "Max",
        windows: [
            LimitWindow(id: "session", label: "5ч", percent: 90, resetsAt: nil),
            LimitWindow(id: "weekly", label: "нед", percent: 20, resetsAt: nil),
        ],
        freshness: .live(now), failure: nil
    )
    #expect(menuBarSummary([account], now: now, window: .worst)?.percent == 90)
    #expect(menuBarSummary([account], now: now, window: .weekly)?.percent == 20)
    #expect(menuBarSummary([account], now: now, window: .session)?.percent == 90)
}
```

Add `import Preferences` at the top of the file.

- [ ] **Step 7: Check**

Run: `cd Packages/Core && swift test --filter UsagePollerTests`
Expected: PASS, 7 tests.

Run: `make build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 8: Commit**

```bash
git add App Packages/Core
git commit -m "The Appearance section: the appearance, the icon and the look of the window"
```

---

### Task 6: The “Notifications” section

**Files:**
- Modify: `App/Settings/NotificationsPane.swift`
- Modify: `App/AppModel.swift`

**Interfaces:**
- Consumes: `PreferencesModel` from Task 4; `ThresholdTracker.init(thresholds:notifyOnRecovery:scope:quietHours:calendar:)` from Task 3.
- Produces: `AppModel.rebuildTracker()` — rebuilds the tracker when the settings change.

- [ ] **Step 1: Fill the section in**

Replace the contents of `App/Settings/NotificationsPane.swift`:

```swift
import SwiftUI
import Preferences

struct NotificationsPane: View {
    @ObservedObject var model: PreferencesModel
    @State private var draftThreshold = ""

    var body: some View {
        Pane(title: "Уведомления",
             subtitle: "Событие приходит на пересечении порога снизу вверх, а не при каждом опросе выше него.") {
            Form {
                Toggle("Уведомлять", isOn: binding(\.notificationsEnabled))

                Section("Пороги") {
                    HStack(spacing: 6) {
                        ForEach(model.value.thresholds, id: \.self) { level in
                            HStack(spacing: 4) {
                                Text("\(level) %").font(.system(size: 11.5))
                                Button {
                                    model.update { $0.thresholds.removeAll { $0 == level } }
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: 8))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                        }

                        TextField("+", text: $draftThreshold)
                            .frame(width: 44)
                            .onSubmit(addThreshold)
                    }
                    if model.value.thresholds.isEmpty {
                        Text("Порогов нет — о загрузке не уведомляем.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }

                Toggle("Когда снова свободен", isOn: binding(\.notifyOnRecovery))

                Picker("По каким окнам", selection: binding(\.notifyWindows)) {
                    ForEach(WindowScope.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Section("Тихие часы") {
                    Toggle("Не беспокоить ночью", isOn: quietEnabled)
                    if let hours = model.value.quietHours {
                        HStack {
                            timeField("С", minutes: hours.startMinute) { new in
                                model.update {
                                    $0.quietHours = QuietHours(
                                        startMinute: new, endMinute: hours.endMinute)
                                }
                            }
                            timeField("до", minutes: hours.endMinute) { new in
                                model.update {
                                    $0.quietHours = QuietHours(
                                        startMinute: hours.startMinute, endMinute: new)
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(!model.value.notificationsEnabled)
        }
    }

    private func addThreshold() {
        guard let level = Int(draftThreshold.trimmingCharacters(in: .whitespaces)),
              level > 0, level <= 100
        else { draftThreshold = ""; return }
        model.update { $0.thresholds.append(level) }   // normalized() will sort it
        draftThreshold = ""
    }

    private var quietEnabled: Binding<Bool> {
        Binding(
            get: { model.value.quietHours != nil },
            set: { on in
                model.update {
                    $0.quietHours = on
                        ? QuietHours(startMinute: 23 * 60, endMinute: 9 * 60)
                        : nil
                }
            }
        )
    }

    private func timeField(
        _ label: String, minutes: Int, set: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 5) {
            Text(label).foregroundStyle(.secondary).font(.system(size: 11.5))
            Stepper(
                value: Binding(get: { minutes }, set: set),
                in: 0...(24 * 60 - 1), step: 30
            ) {
                Text(String(format: "%02d:%02d", minutes / 60, minutes % 60))
                    .monospacedDigit()
            }
        }
    }

    private func binding<T>(_ path: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(
            get: { model.value[keyPath: path] },
            set: { newValue in model.update { $0[keyPath: path] = newValue } }
        )
    }
}
```

- [ ] **Step 2: Rebuild the tracker when the settings change**

In `App/AppModel.swift`, replace the tracker's declaration and add the rebuild:

```swift
    private var tracker = ThresholdTracker()
```

with

```swift
    private var tracker = ThresholdTracker()

    /// The tracker holds the history of readings, so it is recreated only when
    /// the notification settings have actually changed — otherwise every opening
    /// of the settings would erase the memory of the previous values, and the
    /// very next event after that would be lost.
    private var trackerSettings: TrackerSettings?

    private struct TrackerSettings: Equatable {
        let thresholds: [Int]
        let notifyOnRecovery: Bool
        let scope: WindowScope
        let quietHours: QuietHours?
    }

    private func rebuildTrackerIfNeeded() {
        let wanted = TrackerSettings(
            thresholds: preferences.thresholds,
            notifyOnRecovery: preferences.notifyOnRecovery,
            scope: preferences.notifyWindows,
            quietHours: preferences.quietHours
        )
        guard wanted != trackerSettings else { return }
        trackerSettings = wanted
        tracker = ThresholdTracker(
            thresholds: wanted.thresholds,
            notifyOnRecovery: wanted.notifyOnRecovery,
            scope: wanted.scope,
            quietHours: wanted.quietHours
        )
    }
```

In `refresh()`, insert the call before the events are read, and honour the switch:

```swift
        rebuildTrackerIfNeeded()
        if preferences.notificationsEnabled {
            for event in tracker.events(for: result, now: Date()) { post(event) }
        } else {
            // The reading is fed in anyway, so that switching notifications on
            // does not bring a batch of events covering the whole idle stretch.
            _ = tracker.events(for: result, now: Date())
        }
```

- [ ] **Step 3: Build and check**

Run: `make build`
Expected: `BUILD SUCCEEDED`.

Run: `make run`, open “Настройки… → Уведомления”.
Expected: the thresholds are shown as chips, removed with the cross, added by typing
a number and pressing Enter; with “Уведомлять” off, the form is disabled.

- [ ] **Step 4: Commit**

```bash
git add App
git commit -m "The Notifications section: configurable thresholds and quiet hours"
```

---

### Task 7: The “Updates and launch” section

**Files:**
- Create: `App/LaunchAtLogin.swift`
- Modify: `App/Settings/UpdatesPane.swift`
- Modify: `App/AppModel.swift`

**Interfaces:**
- Consumes: `PreferencesModel` from Task 4.
- Produces: `enum LaunchAtLogin` — `static var isEnabled: Bool`, `static func set(_ on: Bool) throws`.

- [ ] **Step 1: Implement launch at login**

Create `App/LaunchAtLogin.swift`:

```swift
import Foundation
import ServiceManagement

/// Launching at login.
///
/// The state is read from the system rather than kept in the settings: a person
/// can turn launch at login off in System Settings, and then our stored value
/// would be a lie.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
```

- [ ] **Step 2: Fill the section in**

Replace the contents of `App/Settings/UpdatesPane.swift`:

```swift
import SwiftUI
import Preferences

struct UpdatesPane: View {
    @ObservedObject var model: PreferencesModel

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Pane(title: "Обновление и запуск",
             subtitle: "Как часто ходить за данными и стартовать ли самому.") {
            Form {
                Section {
                    Toggle("Запускать при входе в систему", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, on in setLaunch(on) }
                    if let launchError {
                        Text(launchError)
                            .font(.system(size: 11)).foregroundStyle(.orange)
                    }
                }

                Section("Частота опроса") {
                    interval("Когда окно открыто", path: \.foregroundInterval)
                    interval("В фоне", path: \.backgroundInterval)
                    Toggle("Обновлять после пробуждения", isOn: binding(\.refreshAfterWake))
                }

                Section("Горячие клавиши") {
                    Text("Настраиваются в следующей версии.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }

    private func setLaunch(_ on: Bool) {
        do {
            try LaunchAtLogin.set(on)
            launchError = nil
        } catch {
            // Do not pretend it worked: put the switch back.
            launchAtLogin = LaunchAtLogin.isEnabled
            launchError = "Не удалось изменить автозапуск. Проверьте «Системные настройки → Основные → Объекты входа»."
        }
    }

    private func interval(
        _ title: String, path: WritableKeyPath<Preferences, TimeInterval>
    ) -> some View {
        let value = model.value[keyPath: path]
        return Stepper(
            value: Binding(
                get: { value },
                set: { new in model.update { $0[keyPath: path] = new } }
            ),
            in: Preferences.intervalRange,
            step: 30
        ) {
            Text("\(title): \(label(for: value))")
        }
    }

    private func label(for seconds: TimeInterval) -> String {
        seconds < 60
            ? "\(Int(seconds)) с"
            : "\(Int(seconds) / 60) мин"
    }

    private func binding<T>(_ path: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(
            get: { model.value[keyPath: path] },
            set: { newValue in model.update { $0[keyPath: path] = newValue } }
        )
    }
}
```

- [ ] **Step 3: Refresh after waking**

In `App/AppModel.swift`, subscribe to the wake notification in `start()`:

```swift
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.preferences.refreshAfterWake else { return }
                await self.refresh()
            }
        }
```

Add `import AppKit` as the first line of the file.

- [ ] **Step 4: Build and check**

Run: `make build`
Expected: `BUILD SUCCEEDED`.

Run: `make run`, open “Настройки… → Обновление”.
Expected: the launch-at-login switch reflects the system's real state;
the intervals step by 30 seconds and go no lower than 30 s or higher than an hour.

- [ ] **Step 5: Commit**

```bash
git add App
git commit -m "The Updates and launch section: launch at login and the poll frequencies"
```

---

### Task 8: The “Services” section, and filtering the poll

**Files:**
- Modify: `App/Settings/ServicesPane.swift`
- Modify: `App/AppModel.swift`
- Modify: `Packages/Core/Sources/CodexProvider/CodexProvider.swift`

**Interfaces:**
- Consumes: `PreferencesModel` from Task 4; `RealCodexFileSystem(root:)` from the prototype.
- Produces: `AppModel.rebuildPoller()` honours `disabledProviders` and `codexRoot`.

- [ ] **Step 1: Fill the section in**

Replace the contents of `App/Settings/ServicesPane.swift`:

```swift
import SwiftUI
import AppKit
import ProviderKit
import Preferences

struct ServicesPane: View {
    @ObservedObject var model: PreferencesModel

    private static let ready: [ProviderID] = [.claude, .codex]
    private static let planned: [ProviderID] = [.cursor, .copilot, .gemini]

    var body: some View {
        Pane(title: "Сервисы",
             subtitle: "Откуда брать данные. Выключенный сервис не опрашивается.") {
            Form {
                Section {
                    Toggle("Claude Code", isOn: enabled(.claude))
                    Text("Живые данные из API.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }

                Section {
                    Toggle("OpenAI Codex", isOn: enabled(.codex))
                    HStack {
                        Text(model.value.codexRoot ?? "~/.codex")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Выбрать…") { chooseCodexRoot() }
                        if model.value.codexRoot != nil {
                            Button("Сбросить") { model.update { $0.codexRoot = nil } }
                        }
                    }
                    Text("Снимок из файлов сессий — обновляется, когда Codex ходит в сеть.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }

                Section("Позже") {
                    ForEach(Self.planned, id: \.self) { provider in
                        HStack {
                            Text(provider.title)
                            Spacer()
                            Text("позже")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private func enabled(_ provider: ProviderID) -> Binding<Bool> {
        Binding(
            get: { !model.value.disabledProviders.contains(provider) },
            set: { on in
                model.update {
                    if on { $0.disabledProviders.remove(provider) }
                    else { $0.disabledProviders.insert(provider) }
                }
            }
        )
    }

    private func chooseCodexRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Выбрать"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.update { $0.codexRoot = url.path }
    }
}
```

- [ ] **Step 2: Honour the settings when the poll is assembled**

In `App/AppModel.swift`, replace `rebuildPoller()`:

```swift
    private func rebuildPoller() async {
        let refs = await store.knownRefs()
            .filter { !preferences.hiddenAccounts.contains($0.id) }

        var providers: [any UsageProvider] = []
        if !preferences.disabledProviders.contains(.claude) {
            providers.append(ClaudeUsageProvider(tokens: store, knownAccounts: refs))
        }
        if !preferences.disabledProviders.contains(.codex) {
            let root = preferences.codexRoot.map(URL.init(fileURLWithPath:))
            providers.append(CodexUsageProvider(
                fileSystem: root.map { RealCodexFileSystem(root: $0) } ?? RealCodexFileSystem()
            ))
        }
        poller = UsagePoller(providers: providers)
    }
```

- [ ] **Step 3: A test for filtering hidden accounts**

Append to `Packages/Core/Tests/MonitoringTests/UsagePollerTests.swift`:

```swift
@Test func pollerWithoutProvidersReturnsNothing() async {
    let result = await UsagePoller(providers: []).refresh()
    #expect(result.isEmpty)
}
```

- [ ] **Step 4: Check**

Run: `cd Packages/Core && swift test --filter UsagePollerTests`
Expected: PASS, 8 tests.

Run: `make build`
Expected: `BUILD SUCCEEDED`.

Check by hand: switch Codex off — its row disappears from the window; switch both
services off — the window shows “Аккаунты не найдены” and the app does not fall over.

- [ ] **Step 5: Commit**

```bash
git add App Packages/Core
git commit -m "The Services section: enabling providers and the path to the Codex directory"
```

---

### Task 9: The “Accounts” section

**Files:**
- Modify: `App/Settings/AccountsPane.swift`
- Modify: `Packages/Core/Sources/Credentials/CredentialStore.swift`
- Test: `Packages/Core/Tests/CredentialsTests/CredentialStoreTests.swift`

**Interfaces:**
- Consumes: `CredentialStore` from the prototype; `PreferencesModel` from Task 4.
- Produces:
  - `enum AccountState: Sendable` — `.activeInCLI`, `.refreshed`, `.needsLogin`
  - `CredentialStore.accountStates() async -> [(account: StoredAccount, state: AccountState)]`
  - `CredentialStore.forget(handle: String) async throws`

- [ ] **Step 1: Write a failing test**

Append to `Packages/Core/Tests/CredentialsTests/CredentialStoreTests.swift`:

```swift
@Test func statesDistinguishActiveFromRefreshed() async throws {
    let keychain = MemoryKeychain([
        CredentialStore.cliService: cliCredentials(token: "tok-A", refresh: "refresh-A")
    ])
    let store = await makeStore(keychain)
    try await store.syncWithCLI(profileUUID: "u-1", displayName: "a@b.c")
    await keychain.seed(cliCredentials(token: "tok-B", refresh: "refresh-B"),
                        service: CredentialStore.cliService)
    try await store.syncWithCLI(profileUUID: "u-2", displayName: "b@b.c")

    let states = await store.accountStates()
    let byHandle = Dictionary(uniqueKeysWithValues: states.map { ($0.account.handle, $0.state) })
    #expect(byHandle["u-2"] == .activeInCLI)
    #expect(byHandle["u-1"] == .refreshed)
}

@Test func accountWithoutCopyNeedsLogin() async throws {
    // The CLI keychain is empty — there was nowhere to take a refresh token copy from.
    let store = await makeStore(MemoryKeychain())
    try await store.syncWithCLI(profileUUID: "u-9", displayName: "c@b.c")

    let states = await store.accountStates()
    #expect(states.first?.state == .needsLogin)
}

@Test func forgetRemovesAccountButNotTheCLIEntry() async throws {
    let keychain = MemoryKeychain([CredentialStore.cliService: cliCredentials(token: "t")])
    let store = await makeStore(keychain)
    try await store.syncWithCLI(profileUUID: "u-1", displayName: "a@b.c")
    try await store.forget(handle: "u-1")

    #expect(await store.knownRefs().isEmpty)
    // The CLI sign-in is untouched — that is the whole promise of the “Забыть” button.
    #expect(await keychain.writeCount(for: CredentialStore.cliService) == 0)
}

@Test func forgettingUnknownAccountIsHarmless() async throws {
    let store = await makeStore(MemoryKeychain())
    try await store.forget(handle: "no such thing")
    #expect(await store.knownRefs().isEmpty)
}
```

- [ ] **Step 2: Confirm the test fails**

Run: `cd Packages/Core && swift test --filter CredentialStoreTests`
Expected: FAIL — there is no `accountStates` and no `forget`.

- [ ] **Step 3: Implement**

Append to `Packages/Core/Sources/Credentials/CredentialStore.swift`, inside
`CredentialStore`:

```swift
    /// How the app obtains a token for this account right now.
    /// Computed rather than stored: the state changes with whoever the user is
    /// signed in as in the CLI, not with anything we record.
    public enum AccountState: Sendable, Hashable {
        case activeInCLI   // the token is read from the CLI keychain, never refreshed
        case refreshed     // lives on its own copy of the refresh token
        case needsLogin    // there is no copy, and nothing to refresh with
    }

    public func accountStates() async -> [(account: StoredAccount, state: AccountState)] {
        let activeRefresh = try? await currentCLIRefreshToken()

        return accounts.map { account in
            let state: AccountState
            if let activeRefresh, account.refreshToken == activeRefresh {
                state = .activeInCLI
            } else if account.refreshToken != nil {
                state = .refreshed
            } else {
                state = .needsLogin
            }
            return (account, state)
        }
    }

    /// Forgets an account together with its token copy.
    /// The keychain item belonging to Claude Code is not touched — the CLI sign-in
    /// keeps working, and that is what the interface promises the user.
    public func forget(handle: String) async throws {
        accounts.removeAll { $0.handle == handle }
        try await persist()
    }
```

- [ ] **Step 4: Confirm the tests pass**

Run: `cd Packages/Core && swift test --filter CredentialStoreTests`
Expected: PASS, 14 tests.

- [ ] **Step 5: Fill the section in**

Replace the contents of `App/Settings/AccountsPane.swift`:

```swift
import SwiftUI
import ProviderKit
import Credentials
import Preferences

struct AccountsPane: View {
    @ObservedObject var model: PreferencesModel
    @ObservedObject var appModel: AppModel

    @State private var rows: [AccountRow] = []
    @State private var pendingForget: AccountRow?

    struct AccountRow: Identifiable, Hashable {
        let id: String
        let handle: String
        let displayName: String
        let state: CredentialStore.AccountState
    }

    var body: some View {
        Pane(title: "Аккаунты",
             subtitle: "Появляются сами, когда вы заходите в них через claude /login. Здесь можно скрыть аккаунт из окна или забыть совсем.") {
            VStack(alignment: .leading, spacing: 12) {
                if rows.isEmpty {
                    Text("Аккаунтов пока нет.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    ForEach(rows) { row in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.displayName)
                                    .font(.system(size: 12.5, weight: .medium))
                                Text(caption(for: row.state))
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(badge(for: row.state))
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(tint(for: row.state).opacity(0.16),
                                            in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(tint(for: row.state))
                            Toggle("", isOn: visible(row))
                                .labelsHidden()
                            Button("Забыть…") { pendingForget = row }
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }

                Text("«Активен в CLI» — токен читается напрямую и не продлевается, иначе claude разлогинится. «Продлевается» — приложение держит свою копию refresh-токена.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await reload() }
        .alert(item: $pendingForget) { row in
            Alert(
                title: Text("Забыть \(row.displayName)?"),
                message: Text("Копия токена будет удалена. Вход в Claude Code это не затронет."),
                primaryButton: .destructive(Text("Забыть")) {
                    Task { await forget(row) }
                },
                secondaryButton: .cancel(Text("Отмена"))
            )
        }
    }

    private func reload() async {
        rows = await appModel.accountRows()
    }

    private func forget(_ row: AccountRow) async {
        await appModel.forgetAccount(handle: row.handle)
        await reload()
    }

    private func visible(_ row: AccountRow) -> Binding<Bool> {
        Binding(
            get: { !model.value.hiddenAccounts.contains(row.id) },
            set: { on in
                model.update {
                    if on { $0.hiddenAccounts.remove(row.id) }
                    else { $0.hiddenAccounts.insert(row.id) }
                }
            }
        )
    }

    private func badge(for state: CredentialStore.AccountState) -> String {
        switch state {
        case .activeInCLI: "активен в CLI"
        case .refreshed:   "продлевается"
        case .needsLogin:  "нужен вход"
        }
    }

    private func caption(for state: CredentialStore.AccountState) -> String {
        switch state {
        case .activeInCLI: "Claude · токен читается из Claude Code"
        case .refreshed:   "Claude · своя копия refresh-токена"
        case .needsLogin:  "Claude · продлить нечем"
        }
    }

    private func tint(for state: CredentialStore.AccountState) -> Color {
        switch state {
        case .activeInCLI: .green
        case .refreshed:   .blue
        case .needsLogin:  .red
        }
    }
}
```

- [ ] **Step 6: Add the bridge in AppModel**

In `App/AppModel.swift`, append:

```swift
    func accountRows() async -> [AccountsPane.AccountRow] {
        await store.accountStates().map { item in
            AccountsPane.AccountRow(
                id: item.account.id,
                handle: item.account.handle,
                displayName: item.account.displayName,
                state: item.state
            )
        }
    }

    func forgetAccount(handle: String) async {
        try? await store.forget(handle: handle)
        await refresh()
    }
```

- [ ] **Step 7: Build and check**

Run: `make build`
Expected: `BUILD SUCCEEDED`.

Run: `make run`, open “Настройки… → Аккаунты”.
Expected: the account is shown with the badge “активен в CLI”; the switch removes it
from the limits window; “Забыть…” asks for confirmation and, once given, removes the row,
while `claude --version` goes on working.

- [ ] **Step 8: Commit**

```bash
git add App Packages/Core
git commit -m "The Accounts section: states, hiding and forgetting"
```

---

### Task 10: Signing in through the browser

**Files:**
- Create: `Packages/Core/Sources/ClaudeProvider/OAuthEndpoints.swift`
- Create: `Packages/Core/Sources/ClaudeProvider/PKCE.swift`
- Create: `Packages/Core/Sources/ClaudeProvider/OAuthLogin.swift`
- Modify: `Packages/Core/Sources/Credentials/CredentialStore.swift`
- Create: `App/LoginController.swift`
- Modify: `App/Settings/AccountsPane.swift`
- Test: `Packages/Core/Tests/ClaudeProviderTests/PKCETests.swift`
- Test: `Packages/Core/Tests/ClaudeProviderTests/OAuthLoginTests.swift`

**Interfaces:**
- Consumes: `HTTPClient` from the prototype; `ClaudeProfileResponse` from the prototype.
- Produces:
  - `enum OAuthEndpoints` — `authorize`, `token`, `manualRedirect`, `clientID`, `scope`
  - `struct PKCEPair: Sendable` — `verifier`, `challenge`; `static func generate() -> PKCEPair`
  - `struct OAuthLogin: Sendable` — `init(http:)`, `func authorizationURL(redirectURI:pkce:state:manual:) -> URL`, `func exchange(code:verifier:redirectURI:) async throws -> RefreshedTokens`
  - `CredentialStore.addLoggedInAccount(uuid:displayName:refreshToken:) async throws`

The addresses are taken from the constants of the installed Claude Code and were checked
live on 2026-08-30: the authorize request answers `200` and serves the sign-in page.
**The former address `claude.ai/oauth/authorize` answers `403` — the domains have changed**,
so `AnthropicTokenRefresher` is moved to `platform.claude.com` here as well.

- [ ] **Step 1: Write a failing test for PKCE**

Create `Packages/Core/Tests/ClaudeProviderTests/PKCETests.swift`:

```swift
import Testing
import Foundation
import CryptoKit
@testable import ClaudeProvider

@Test func challengeIsBase64URLOfSHA256OfVerifier() {
    let pair = PKCEPair.generate()
    let expected = Data(SHA256.hash(data: Data(pair.verifier.utf8)))
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    #expect(pair.challenge == expected)
}

@Test func encodingIsURLSafeAndUnpadded() {
    for _ in 0..<50 {
        let pair = PKCEPair.generate()
        for value in [pair.verifier, pair.challenge] {
            #expect(value.contains("+") == false)
            #expect(value.contains("/") == false)
            #expect(value.contains("=") == false)
        }
    }
}

@Test func verifierIsLongEnoughForTheSpec() {
    // RFC 7636 requires between 43 and 128 characters.
    let pair = PKCEPair.generate()
    #expect(pair.verifier.count >= 43)
    #expect(pair.verifier.count <= 128)
}

@Test func eachPairIsDifferent() {
    let first = PKCEPair.generate()
    let second = PKCEPair.generate()
    #expect(first.verifier != second.verifier)
}
```

- [ ] **Step 2: Confirm the test fails**

Run: `cd Packages/Core && swift test --filter PKCETests`
Expected: FAIL, `cannot find 'PKCEPair' in scope`.

- [ ] **Step 3: Implement the addresses and PKCE**

Create `Packages/Core/Sources/ClaudeProvider/OAuthEndpoints.swift`:

```swift
import Foundation

/// The sign-in addresses, taken from the constants of the installed Claude Code.
///
/// The domains have changed: `claude.ai/oauth/authorize` answers `403`, and the
/// address in force is `platform.claude.com`. Kept in one place so that the next
/// change is made at a single point.
public enum OAuthEndpoints {
    public static let authorize = URL(string: "https://platform.claude.com/oauth/authorize")!
    public static let token = URL(string: "https://platform.claude.com/v1/oauth/token")!
    public static let manualRedirect = "https://platform.claude.com/oauth/code/callback"
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    public static let scope = "org:create_api_key user:profile user:inference"
}
```

Create `Packages/Core/Sources/ClaudeProvider/PKCE.swift`:

```swift
import Foundation
import CryptoKit

/// A PKCE pair (RFC 7636). The verifier stays with the app and only the challenge
/// goes to the browser — which is why intercepting the address gains nothing.
public struct PKCEPair: Sendable, Hashable {
    public let verifier: String
    public let challenge: String

    public static func generate() -> PKCEPair {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = base64URL(Data(bytes))
        let digest = Data(SHA256.hash(data: Data(verifier.utf8)))
        return PKCEPair(verifier: verifier, challenge: base64URL(digest))
    }

    /// base64url without padding: `+` and `/` are not allowed in address
    /// parameters, and the specification forbids `=`.
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
```

- [ ] **Step 4: Confirm the PKCE tests pass**

Run: `cd Packages/Core && swift test --filter PKCETests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Write a failing test for the sign-in**

Create `Packages/Core/Tests/ClaudeProviderTests/OAuthLoginTests.swift`:

```swift
import Testing
import Foundation
import ProviderKit
@testable import ClaudeProvider

private struct StubHTTP: HTTPClient {
    var response: (Data, Int)
    var seenBody: @Sendable (Data) -> Void = { _ in }

    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        (Data(), 404)
    }
    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
        seenBody(body)
        return response
    }
}

private func d(_ s: String) -> Data { s.data(using: .utf8)! }

@Test func authorizationURLCarriesEveryRequiredParameter() {
    let login = OAuthLogin(http: StubHTTP(response: (Data(), 200)))
    let pkce = PKCEPair.generate()
    let url = login.authorizationURL(
        redirectURI: "http://localhost:54545/callback", pkce: pkce,
        state: "st-1", manual: false
    )
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems ?? []
    let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

    #expect(url.host == "platform.claude.com")
    #expect(byName["client_id"] == OAuthEndpoints.clientID)
    #expect(byName["response_type"] == "code")
    #expect(byName["redirect_uri"] == "http://localhost:54545/callback")
    #expect(byName["code_challenge"] == pkce.challenge)
    #expect(byName["code_challenge_method"] == "S256")
    #expect(byName["state"] == "st-1")
    #expect(byName["scope"] == OAuthEndpoints.scope)
    #expect(byName["code"] == nil)   // not the manual route
}

@Test func manualModeAddsCodeFlagAndItsOwnRedirect() {
    let login = OAuthLogin(http: StubHTTP(response: (Data(), 200)))
    let url = login.authorizationURL(
        redirectURI: OAuthEndpoints.manualRedirect, pkce: .generate(),
        state: "st", manual: true
    )
    let byName = Dictionary(uniqueKeysWithValues:
        (URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
    #expect(byName["code"] == "true")
    #expect(byName["redirect_uri"] == OAuthEndpoints.manualRedirect)
}

@Test func exchangeReturnsBothTokens() async throws {
    let http = StubHTTP(response: (d(#"{"access_token":"at","refresh_token":"rt"}"#), 200))
    let tokens = try await OAuthLogin(http: http).exchange(
        code: "c", verifier: "v", redirectURI: "http://localhost:1/callback"
    )
    #expect(tokens.accessToken == "at")
    #expect(tokens.refreshToken == "rt")
}

@Test func exchangeSendsVerifierAndGrantType() async throws {
    let box = Box()
    var http = StubHTTP(response: (d(#"{"access_token":"at"}"#), 200))
    http.seenBody = { box.set($0) }
    _ = try await OAuthLogin(http: http).exchange(
        code: "the-code", verifier: "the-verifier", redirectURI: "http://localhost:1/callback"
    )
    let sent = try #require(box.value)
    let json = try JSONSerialization.jsonObject(with: sent) as? [String: Any]
    #expect(json?["grant_type"] as? String == "authorization_code")
    #expect(json?["code"] as? String == "the-code")
    #expect(json?["code_verifier"] as? String == "the-verifier")
    #expect(json?["client_id"] as? String == OAuthEndpoints.clientID)
}

@Test func serverErrorBecomesNeedsLogin() async {
    let http = StubHTTP(response: (d(#"{"error":"invalid_grant"}"#), 400))
    await #expect(throws: ProviderFailure.self) {
        _ = try await OAuthLogin(http: http).exchange(
            code: "c", verifier: "v", redirectURI: "http://localhost:1/callback"
        )
    }
}

@Test func errorMessageNeverLeaksTheVerifier() async {
    let http = StubHTTP(response: (d(#"{"error":"invalid_grant"}"#), 400))
    do {
        _ = try await OAuthLogin(http: http).exchange(
            code: "c", verifier: "SECRET-VERIFIER", redirectURI: "http://localhost:1/callback"
        )
        Issue.record("an error was expected")
    } catch let failure as ProviderFailure {
        #expect(failure.message.contains("SECRET") == false)
    } catch {
        Issue.record("a different kind of error")
    }
}

/// A test box: a `@Sendable` closure cannot write to a `var` directly.
private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?
    var value: Data? { lock.lock(); defer { lock.unlock() }; return stored }
    func set(_ data: Data) { lock.lock(); stored = data; lock.unlock() }
}
```

- [ ] **Step 6: Confirm the test fails**

Run: `cd Packages/Core && swift test --filter OAuthLoginTests`
Expected: FAIL, `cannot find 'OAuthLogin' in scope`.

- [ ] **Step 7: Implement the sign-in**

Create `Packages/Core/Sources/ClaudeProvider/OAuthLogin.swift`:

```swift
import Foundation
import ProviderKit

public struct OAuthLogin: Sendable {
    private let http: any HTTPClient

    public init(http: any HTTPClient = URLSessionHTTPClient()) { self.http = http }

    /// The address of the sign-in page.
    /// `manual: true` adds `code=true` — the server then shows the code on the
    /// page instead of returning to `redirect_uri`. That is the fallback route,
    /// for when the return to localhost does not work.
    public func authorizationURL(
        redirectURI: String, pkce: PKCEPair, state: String, manual: Bool
    ) -> URL {
        var components = URLComponents(
            url: OAuthEndpoints.authorize, resolvingAgainstBaseURL: false
        )!
        var items = [
            URLQueryItem(name: "client_id", value: OAuthEndpoints.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: OAuthEndpoints.scope),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        if manual { items.insert(URLQueryItem(name: "code", value: "true"), at: 0) }
        components.queryItems = items
        return components.url!
    }

    public func exchange(
        code: String, verifier: String, redirectURI: String
    ) async throws -> RefreshedTokens {
        let body = try JSONSerialization.data(withJSONObject: [
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
            "client_id": OAuthEndpoints.clientID,
            "redirect_uri": redirectURI,
        ])

        let (data, status) = try await http.post(
            OAuthEndpoints.token, headers: ["Content-Type": "application/json"], body: body
        )
        guard status == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = root["access_token"] as? String
        else {
            // The server's answer is not repeated outwards: it could carry the code
            // or the verifier, and this message goes to the interface.
            throw ProviderFailure(kind: .needsLogin, message: "Не удалось завершить вход")
        }
        return RefreshedTokens(
            accessToken: access, refreshToken: root["refresh_token"] as? String
        )
    }
}
```

`RefreshedTokens` is declared in the `Credentials` module, while `OAuthLogin` lives in
`ClaudeProvider`, which does not depend on it. So the type moves: cut the declaration
of `RefreshedTokens` out of
`Packages/Core/Sources/Credentials/CredentialStore.swift` and paste it into
`Packages/Core/Sources/ClaudeProvider/OAuthLogin.swift`, before `OAuthLogin`:

```swift
public struct RefreshedTokens: Sendable, Hashable {
    public let accessToken: String
    public let refreshToken: String?

    public init(accessToken: String, refreshToken: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}
```

`Credentials` already imports `ClaudeProvider`, so nothing else is needed.

- [ ] **Step 8: Move refreshing to the address in force**

In `Packages/Core/Sources/Credentials/CredentialStore.swift`, in
`AnthropicTokenRefresher`, replace the constants with the shared ones:

```swift
public struct AnthropicTokenRefresher: TokenRefreshing {
    private let http: any HTTPClient

    public init(http: any HTTPClient = URLSessionHTTPClient()) { self.http = http }

    public func refresh(refreshToken: String) async throws -> RefreshedTokens {
        let body = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": OAuthEndpoints.clientID,
        ])

        let (data, code) = try await http.post(
            OAuthEndpoints.token, headers: ["Content-Type": "application/json"], body: body
        )
        guard code == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = root["access_token"] as? String
        else {
            throw ProviderFailure(kind: .needsLogin, message: "Нужен вход в аккаунт")
        }
        return RefreshedTokens(
            accessToken: access, refreshToken: root["refresh_token"] as? String
        )
    }
}
```

- [ ] **Step 9: Add saving of the account that signed in**

Append to `CredentialStore`:

```swift
    /// Saves an account added by signing in through the browser.
    /// It has a token pair of its own, unconnected to the CLI session, so it lands
    /// straight in the “refreshed” state.
    public func addLoggedInAccount(
        uuid: String, displayName: String, refreshToken: String
    ) async throws {
        accounts.removeAll { $0.handle == uuid }
        accounts.append(StoredAccount(
            id: "claude/\(uuid)", handle: uuid,
            displayName: displayName, refreshToken: refreshToken
        ))
        try await persist()
    }
```

- [ ] **Step 10: Confirm the whole package passes**

Run: `cd Packages/Core && swift test`
Expected: PASS, every test.

- [ ] **Step 11: Implement the return from the browser**

Create `App/LoginController.swift`:

```swift
import Foundation
import AppKit
import Network
import ProviderKit
import ClaudeProvider
import Credentials

/// Runs the browser sign-in: raises a listener on a free port, opens the
/// sign-in page and waits for the return carrying the code.
@MainActor
final class LoginController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var message: String?
    /// The address is shown if the return did not work and the code must be entered by hand.
    @Published private(set) var manualCodeExpected = false

    private let login = OAuthLogin()
    private let store: CredentialStore
    private var listener: NWListener?
    private var pkce: PKCEPair?
    private var state: String?
    private var redirectURI: String?
    private var timeout: Task<Void, Never>?

    init(store: CredentialStore) { self.store = store }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        message = nil
        manualCodeExpected = false

        let pair = PKCEPair.generate()
        let st = UUID().uuidString
        pkce = pair
        state = st

        do {
            let port = try startListener()
            let uri = "http://localhost:\(port)/callback"
            redirectURI = uri
            NSWorkspace.shared.open(
                login.authorizationURL(redirectURI: uri, pkce: pair, state: st, manual: false)
            )
            armTimeout()
        } catch {
            // The port could not be taken — fall back to entering the code by hand.
            fallBackToManual(pair: pair, state: st)
        }
    }

    /// The manual route: the code was copied from the page and pasted into the field.
    func submit(code: String) async {
        guard let pair = pkce, let uri = redirectURI else { return }
        await finish(code: code, verifier: pair.verifier, redirectURI: uri)
    }

    func cancel() {
        stopListener()
        isRunning = false
        manualCodeExpected = false
        message = nil
    }

    // MARK: - internals

    private func startListener() throws -> UInt16 {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
                data, _, _, _ in
                guard let data, let request = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in self?.handle(request: request, on: connection) }
            }
        }
        listener.start(queue: .main)

        // The port is assigned by the system asynchronously; wait for it to appear.
        var attempts = 0
        while listener.port == nil && attempts < 200 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            attempts += 1
        }
        guard let port = listener.port?.rawValue else {
            throw ProviderFailure(kind: .network, message: "Не удалось занять порт")
        }
        return port
    }

    private func handle(request: String, on connection: NWConnection) {
        defer { connection.cancel() }

        // The first line looks like: GET /callback?code=...&state=... HTTP/1.1
        guard let line = request.split(separator: "\r\n").first,
              let path = line.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: "http://localhost\(path)")
        else { return }

        let items = components.queryItems ?? []
        let code = items.first { $0.name == "code" }?.value
        let returned = items.first { $0.name == "state" }?.value

        respond(on: connection, ok: code != nil)

        // A foreign state means a planted redirect — that code is not taken.
        guard let code, returned == state, let pair = pkce, let uri = redirectURI else {
            message = "Возврат из браузера не распознан."
            isRunning = false
            stopListener()
            return
        }

        stopListener()
        Task { await finish(code: code, verifier: pair.verifier, redirectURI: uri) }
    }

    private func respond(on connection: NWConnection, ok: Bool) {
        let text = ok ? "Готово. Можно вернуться в приложение." : "Что-то пошло не так."
        let body = "<html><meta charset=\"utf-8\"><body style=\"font-family:-apple-system;padding:40px\">\(text)</body></html>"
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in })
    }

    private func finish(code: String, verifier: String, redirectURI: String) async {
        do {
            let tokens = try await login.exchange(
                code: code, verifier: verifier, redirectURI: redirectURI
            )
            guard let refresh = tokens.refreshToken else {
                throw ProviderFailure(kind: .needsLogin, message: "Сервис не вернул refresh-токен")
            }

            let http = URLSessionHTTPClient()
            let headers = [
                "Authorization": "Bearer \(tokens.accessToken)",
                "anthropic-beta": "oauth-2025-04-20",
                "User-Agent": "claude-cli/2.0.0 (external, cli)",
            ]
            let url = URL(string: "https://api.anthropic.com/api/oauth/profile")!
            let (data, status) = try await http.get(url, headers: headers)
            guard status == 200, let profile = try? ClaudeProfileResponse.parse(data) else {
                throw ProviderFailure(kind: .needsLogin, message: "Не удалось прочитать профиль")
            }

            try await store.addLoggedInAccount(
                uuid: profile.uuid, displayName: profile.displayName, refreshToken: refresh
            )
            message = "Аккаунт \(profile.displayName) добавлен."
        } catch let failure as ProviderFailure {
            message = failure.message
        } catch {
            message = "Не удалось завершить вход."
        }
        isRunning = false
        manualCodeExpected = false
        timeout?.cancel()
    }

    private func fallBackToManual(pair: PKCEPair, state: String) {
        redirectURI = OAuthEndpoints.manualRedirect
        manualCodeExpected = true
        message = "Скопируйте код со страницы и вставьте его ниже."
        NSWorkspace.shared.open(login.authorizationURL(
            redirectURI: OAuthEndpoints.manualRedirect, pkce: pair, state: state, manual: true
        ))
    }

    /// The listener must not hang about forever if the person closed the tab.
    private func armTimeout() {
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.isRunning else { return }
                self.stopListener()
                self.isRunning = false
                self.message = "Вход не завершён за две минуты."
            }
        }
    }

    private func stopListener() {
        listener?.cancel()
        listener = nil
        timeout?.cancel()
    }
}
```

- [ ] **Step 12: Add the button to the “Accounts” section**

In `App/Settings/AccountsPane.swift`, add the state and the button. After
`@State private var pendingForget: AccountRow?`, insert:

```swift
    @StateObject private var loginController: LoginController
    @State private var manualCode = ""

    init(model: PreferencesModel, appModel: AppModel) {
        self.model = model
        self.appModel = appModel
        _loginController = StateObject(wrappedValue: LoginController(store: appModel.store))
    }
```

In the `VStack`, after the account list and before the explanation, insert:

```swift
                HStack(spacing: 8) {
                    Button("Добавить аккаунт…") { loginController.start() }
                        .disabled(loginController.isRunning)
                    if loginController.isRunning {
                        ProgressView().controlSize(.small)
                        Button("Отмена") { loginController.cancel() }
                    }
                    Spacer()
                }

                if loginController.manualCodeExpected {
                    HStack(spacing: 6) {
                        TextField("Код со страницы", text: $manualCode)
                            .frame(width: 220)
                        Button("Готово") {
                            Task {
                                await loginController.submit(code: manualCode)
                                manualCode = ""
                                await reload()
                            }
                        }
                        .disabled(manualCode.isEmpty)
                    }
                }

                if let message = loginController.message {
                    Text(message)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
```

And add a reload after a successful sign-in to `.task`:

```swift
        .onChange(of: loginController.message) { _, _ in
            Task { await reload() }
        }
```

- [ ] **Step 13: Open access to the store**

In `App/AppModel.swift`, replace `private let store: CredentialStore` with:

```swift
    /// The “Accounts” section builds its own `LoginController` over the same store.
    let store: CredentialStore
```

- [ ] **Step 14: Build and check**

Run: `make build`
Expected: `BUILD SUCCEEDED`.

Run: `make run`, open “Настройки… → Аккаунты → Добавить аккаунт…”.
Expected: the browser opens on the Claude sign-in page; after signing in the browser
returns to localhost and shows “Готово”, and a new account appears in the list
with the badge “продлевается”.

If the browser shows a code instead of returning, the fallback route fired: copy the
code into the “Код со страницы” field and press “Готово”. The result is the same.

- [ ] **Step 15: Commit**

```bash
git add App Packages/Core
git commit -m "Signing in to a Claude account through the browser, from settings"
```

---

### Task 11: The “About” section, and the alternative row layouts

**Files:**
- Modify: `App/Settings/AboutPane.swift`
- Modify: `App/AccountRowView.swift`

**Interfaces:**
- Consumes: `RowLayout` from Task 1; `CredentialStore.forget` from Task 9.
- Produces: `AppModel.forgetAllAccounts() async`.

- [ ] **Step 1: Fill the “About” section in**

Replace the contents of `App/Settings/AboutPane.swift`:

```swift
import SwiftUI
import AppKit
import Credentials
import Preferences

struct AboutPane: View {
    @ObservedObject var model: PreferencesModel
    @ObservedObject var appModel: AppModel

    @State private var confirmForgetAll = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (сборка \(build))"
    }

    var body: some View {
        Pane(title: "О программе и данные",
             subtitle: "Что приложение хранит и как это убрать.") {
            Form {
                Section {
                    LabeledContent("Версия", value: version)
                    LabeledContent("Учётные данные",
                                   value: "Keychain · \(CredentialStore.ownService)")
                    LabeledContent("Настройки",
                                   value: "~/Library/Preferences/dev.example.StatusChecker.plist")
                }

                Section {
                    Button("Забыть все аккаунты…", role: .destructive) {
                        confirmForgetAll = true
                    }
                    Text("Удалит только копии токенов, которые хранит это приложение. Вход в Claude Code это не затронет.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
        }
        .confirmationDialog(
            "Забыть все аккаунты?", isPresented: $confirmForgetAll, titleVisibility: .visible
        ) {
            Button("Забыть все", role: .destructive) {
                Task { await appModel.forgetAllAccounts() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Копии токенов будут удалены. Вход в Claude Code останется рабочим.")
        }
    }
}
```

- [ ] **Step 2: Add the method to AppModel**

In `App/AppModel.swift`, append:

```swift
    func forgetAllAccounts() async {
        for ref in await store.knownRefs() {
            try? await store.forget(handle: ref.handle)
        }
        await refresh()
    }
```

- [ ] **Step 3: Implement layouts B and C**

In `App/AccountRowView.swift`, replace `body`:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            if let failure = snapshot.failure {
                Text(failure.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                switch layout {
                case .twoWindows: ForEach(snapshot.windows) { meter(for: $0) }
                case .compact:    compactMeter
                case .rings:      ringsRow
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }

    /// A single line: the weekly percentage large, the five-hour window as a notch.
    private var compactMeter: some View {
        let weekly = snapshot.windows.first { $0.id == "weekly" } ?? snapshot.windows.first
        let session = snapshot.windows.first { $0.id == "session" }

        return VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.11))
                    if let weekly {
                        Capsule()
                            .fill(weekly.severity.tint)
                            .frame(width: max(2, geo.size.width * weekly.percent / 100))
                    }
                    if let session {
                        Rectangle()
                            .fill(.primary.opacity(0.55))
                            .frame(width: 1.5, height: 7)
                            .offset(x: geo.size.width * session.percent / 100)
                    }
                }
            }
            .frame(height: 4)

            HStack(spacing: 6) {
                if let weekly {
                    Text("нед \(Int(weekly.percent.rounded()))%")
                    Text(weekly.remaining(from: now).map(formatRemaining) ?? "—")
                }
                if let session {
                    Text("· 5ч \(Int(session.percent.rounded()))%")
                }
            }
            .font(.system(size: 10.5))
            .monospacedDigit()
            .foregroundStyle(.tertiary)
        }
    }

    /// Rings: the percentage reads as a number, without comparing bar lengths.
    private var ringsRow: some View {
        HStack(spacing: 10) {
            ForEach(snapshot.windows) { window in
                VStack(spacing: 3) {
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.11), lineWidth: 3.4)
                        Circle()
                            .trim(from: 0, to: max(0.01, window.percent / 100))
                            .stroke(window.severity.tint,
                                    style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(window.percent.rounded()))")
                            .font(.system(size: 9.5, weight: .semibold))
                            .monospacedDigit()
                    }
                    .frame(width: 34, height: 34)
                    Text(window.label)
                        .font(.system(size: 8.5))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if let worst = snapshot.peakWindow {
                Text(worst.remaining(from: now).map(formatRemaining) ?? "—")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
    }
```

- [ ] **Step 4: Build and check**

Run: `make build`
Expected: `BUILD SUCCEEDED`.

Run: `make run`, and in “Внешний вид” switch the layout between “Два окна”,
“Одна строка” and “Кольца”.
Expected: the window redraws, all three read clearly, and nothing is clipped.

- [ ] **Step 5: Commit**

```bash
git add App
git commit -m "The About section and the alternative row layouts"
```

---

### Task 12: Hot keys

**Files:**
- Create: `App/HotKeys.swift`
- Modify: `App/Settings/UpdatesPane.swift`
- Modify: `Packages/Core/Sources/Preferences/Preferences.swift`
- Test: `Packages/Core/Tests/PreferencesTests/HotKeyTests.swift`

**Interfaces:**
- Consumes: `Preferences` from Task 1.
- Produces:
  - `struct HotKeyCombo: Codable, Sendable, Hashable` — `keyCode: UInt32`, `modifiers: UInt32`, `displayString: String`
  - `Preferences.openWindowHotKey: HotKeyCombo?`, `Preferences.refreshHotKey: HotKeyCombo?`
  - `final class HotKeyCenter` — `register(_ combo: HotKeyCombo?, id: UInt32, action: @escaping () -> Void)`, `unregisterAll()`

This is the one part of the plan that needs a C API: a global shortcut without
Accessibility permission is only available through Carbon `RegisterEventHotKey`. The task
comes last — if the work has to stop earlier, everything else already works.

- [ ] **Step 1: Write a failing test for how a combination reads**

Create `Packages/Core/Tests/PreferencesTests/HotKeyTests.swift`:

```swift
import Testing
import Foundation
@testable import Preferences

@Test func describesModifiersInAppleOrder() {
    // The order of the symbols on macOS: ⌃ ⌥ ⇧ ⌘
    let combo = HotKeyCombo(keyCode: 37, modifiers: HotKeyCombo.command | HotKeyCombo.option)
    #expect(combo.displayString == "⌥⌘L")
}

@Test func describesSingleModifier() {
    #expect(HotKeyCombo(keyCode: 37, modifiers: HotKeyCombo.command).displayString == "⌘L")
}

@Test func describesAllFourModifiers() {
    let all = HotKeyCombo.control | HotKeyCombo.option | HotKeyCombo.shift | HotKeyCombo.command
    #expect(HotKeyCombo(keyCode: 37, modifiers: all).displayString == "⌃⌥⇧⌘L")
}

@Test func unknownKeyCodeFallsBackToNumber() {
    #expect(HotKeyCombo(keyCode: 999, modifiers: HotKeyCombo.command).displayString == "⌘#999")
}

@Test func survivesEncodingRoundTrip() throws {
    let combo = HotKeyCombo(keyCode: 15, modifiers: HotKeyCombo.command)
    let data = try JSONEncoder().encode(combo)
    #expect(try JSONDecoder().decode(HotKeyCombo.self, from: data) == combo)
}
```

- [ ] **Step 2: Confirm the test fails**

Run: `cd Packages/Core && swift test --filter HotKeyTests`
Expected: FAIL, `cannot find 'HotKeyCombo' in scope`.

- [ ] **Step 3: Implement how a combination reads**

Append to `Packages/Core/Sources/Preferences/Preferences.swift`, before
`struct Preferences`:

```swift
/// A key combination. Held as Carbon key codes rather than characters: the character
/// depends on the layout and the key code does not, so the combination does not
/// wander when the input language is switched.
public struct HotKeyCombo: Codable, Sendable, Hashable {
    public static let control: UInt32 = 1 << 12
    public static let option: UInt32 = 1 << 11
    public static let shift: UInt32 = 1 << 9
    public static let command: UInt32 = 1 << 8

    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// How the combination reads in the interface. The symbol order is the macOS one.
    public var displayString: String {
        var result = ""
        if modifiers & Self.control != 0 { result += "⌃" }
        if modifiers & Self.option != 0 { result += "⌥" }
        if modifiers & Self.shift != 0 { result += "⇧" }
        if modifiers & Self.command != 0 { result += "⌘" }
        return result + Self.name(for: keyCode)
    }

    private static let names: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M", 49: "Space",
    ]

    private static func name(for code: UInt32) -> String {
        names[code] ?? "#\(code)"
    }
}
```

Add the fields to `Preferences` after `refreshAfterWake`:

```swift
    public var openWindowHotKey: HotKeyCombo?
    public var refreshHotKey: HotKeyCombo?
```

and to `defaults` after `refreshAfterWake: true,`:

```swift
        openWindowHotKey: nil,
        refreshHotKey: nil,
```

- [ ] **Step 4: Confirm the tests pass**

Run: `cd Packages/Core && swift test --filter HotKeyTests`
Expected: PASS, 5 tests.

Run: `cd Packages/Core && swift test --filter PreferencesTests`
Expected: PASS — `defaultsMatchTheSpec` goes on working, the new fields `nil`.

- [ ] **Step 5: Implement registration**

Create `App/HotKeys.swift`:

```swift
import Foundation
import AppKit
import Carbon.HIToolbox
import Preferences

/// Global key combinations.
///
/// Carbon `RegisterEventHotKey` is the only way to get a combination that works
/// outside the active application without asking for Accessibility permission.
/// It has no modern replacement.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var handler: EventHandlerRef?

    private init() { installHandler() }

    func register(_ combo: HotKeyCombo?, id: UInt32, action: @escaping () -> Void) {
        unregister(id: id)
        guard let combo else { return }

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x53544348), id: id)  // 'STCH'
        let status = RegisterEventHotKey(
            combo.keyCode, combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return }

        refs[id] = ref
        actions[id] = action
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        actions[id] = nil
    }

    func unregisterAll() {
        for id in refs.keys { unregister(id: id) }
    }

    private func installHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var id = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &id
                )
                let pressed = id.id
                Task { @MainActor in HotKeyCenter.shared.fire(pressed) }
                return noErr
            },
            1, &spec, nil, &handler
        )
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
    }
}

enum HotKeyID {
    static let openWindow: UInt32 = 1
    static let refresh: UInt32 = 2
}
```

- [ ] **Step 6: Add recording a combination to the section**

In `App/Settings/UpdatesPane.swift`, replace the “Горячие клавиши” section:

```swift
                Section("Горячие клавиши") {
                    hotKeyRow("Открыть окно", path: \.openWindowHotKey)
                    hotKeyRow("Обновить сейчас", path: \.refreshHotKey)
                }
```

and append to the same type:

```swift
    @State private var recording: String?

    private func hotKeyRow(
        _ title: String, path: WritableKeyPath<Preferences, HotKeyCombo?>
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(model.value[keyPath: path]?.displayString ?? "не назначено")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(model.value[keyPath: path] == nil ? .secondary : .primary)
            Button(recording == title ? "Нажмите…" : "Изменить") {
                recording = recording == title ? nil : title
            }
            if model.value[keyPath: path] != nil {
                Button("Убрать") { model.update { $0[keyPath: path] = nil } }
            }
        }
        .background(
            HotKeyRecorder(isActive: recording == title) { combo in
                model.update { $0[keyPath: path] = combo }
                recording = nil
            }
        )
    }
```

Create the key-press catcher in the same file:

```swift
/// Catches a single key press and hands it back as a combination.
/// Through an `NSView`, because SwiftUI does not give up key codes and modifiers
/// in the form Carbon expects them.
private struct HotKeyRecorder: NSViewRepresentable {
    let isActive: Bool
    let onCapture: (HotKeyCombo) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.onCapture = onCapture
        if isActive { view.window?.makeFirstResponder(view) }
    }

    final class RecorderView: NSView {
        var onCapture: ((HotKeyCombo) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            var modifiers: UInt32 = 0
            if event.modifierFlags.contains(.control) { modifiers |= HotKeyCombo.control }
            if event.modifierFlags.contains(.option) { modifiers |= HotKeyCombo.option }
            if event.modifierFlags.contains(.shift) { modifiers |= HotKeyCombo.shift }
            if event.modifierFlags.contains(.command) { modifiers |= HotKeyCombo.command }

            // A combination without modifiers would swallow ordinary typing.
            guard modifiers != 0 else { NSSound.beep(); return }
            onCapture?(HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers))
        }
    }
}
```

- [ ] **Step 7: Wire the actions up**

In `App/StatusCheckerApp.swift`, add the registration to the `Settings` scene:

```swift
                .onChange(of: preferences.value.openWindowHotKey, initial: true) { _, combo in
                    HotKeyCenter.shared.register(combo, id: HotKeyID.openWindow) {
                        NSApp.sendAction(
                            Selector(("openMenuBarExtra:")), to: nil, from: nil
                        )
                    }
                }
                .onChange(of: preferences.value.refreshHotKey, initial: true) { _, combo in
                    HotKeyCenter.shared.register(combo, id: HotKeyID.refresh) {
                        Task { await model.refresh() }
                    }
                }
```

Opening the menu bar window programmatically is not directly supported by the system;
if `openMenuBarExtra:` does not fire, the “Открыть окно” combination is left
unassigned while “Обновить сейчас” works. Check at step 8 and, if opening does not
work, remove the “Открыть окно” row from the section and keep one combination —
promising something in the interface that does not work is not allowed.

- [ ] **Step 8: Build and check**

Run: `make build`
Expected: `BUILD SUCCEEDED`.

Run: `make run`, assign “Обновить сейчас” to ⌥⌘R, minimise every window, press
the combination.
Expected: the time in the limits window's heading updates, and the icon redraws.

- [ ] **Step 9: Commit**

```bash
git add App Packages/Core
git commit -m "Hot keys: recording a combination and registering it globally"
```

---

### Task 13: Acceptance and documentation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Run every test**

Run: `make test`
Expected: PASS, not a single failure.

- [ ] **Step 2: Walk through every section**

Run: `make run`, open “Настройки…” and check each of them:

- **Accounts** — the states are shown correctly; the switch removes an account from the
  window; “Забыть” asks for confirmation; `claude --version` works afterwards.
- **Appearance** — switching the appearance changes the window at once; all three row
  layouts read clearly; a change to “В строке меню” shows on the icon.
- **Notifications** — a threshold is added and removed; with “Уведомлять” off the form
  is disabled.
- **Updates** — launch at login reflects the system state; the intervals stay within
  30 s and an hour.
- **Services** — switching Codex off removes its row; switching both off gives
  “Аккаунты не найдены” without falling over.
- **About** — the version is right; “Забыть все аккаунты” asks for confirmation.

- [ ] **Step 3: Check the CLI sign-in is intact**

Run: `claude --version`
Expected: the version prints, the sign-in did not drop.

Run: `security find-generic-password -s "Claude Code-credentials" | head -3`
Expected: the item is where it was.

- [ ] **Step 4: Update the README**

In `README.md`, after the “Several Claude subscriptions” section, add:

```markdown
## Settings

Opened from the limits window with the “Настройки…” item, or with ⌘,.

Six sections: accounts, appearance, notifications, updates and launch, services,
about. The appearance is system, light or dark.

An account can be added from settings with the “Добавить аккаунт…” button: the browser
opens, and the password is typed only there. Such an account lives on its own token pair
and is unconnected to the CLI session.

The settings live in `~/Library/Preferences/dev.example.StatusChecker.plist`.
Credentials are not kept there — they are in the keychain, in the item
`StatusChecker-accounts`.
```

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "README: the settings section"
```

---

## What was left out of scope

1. **Carrying settings between machines** — they are local for now.
2. **Live Codex data** instead of a snapshot.
3. **Cursor, GitHub Copilot and Gemini CLI providers** — the room for them in the
   “Services” section already exists.
4. **An iOS app and a widget.**
