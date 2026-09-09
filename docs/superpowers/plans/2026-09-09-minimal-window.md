# Minimal window implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One setting turns the limits window into one line per account — no header, no dividers, no badges, no plan labels, colour only when a limit is close — and the status item's menu gains the switch for it along with "Add account…" and "Statistics…".

**Architecture:** A `Bool` in `Preferences`, a pure `headlineWindow(for:)` on `AccountSnapshot`, a second row view `MinimalAccountRow` beside `AccountRow` in `StatusUI`, and a branch in `PopoverView`. The widgets and the phone keep drawing `AccountRow` and are untouched. `LoginController` moves from `AccountsPane` to `AppModel` so the menu can start a sign-in.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit (`NSStatusItem`, `NSMenu`, `NSPopover`), Swift Testing, SwiftPM package in `Packages/Core`.

**Spec:** `docs/superpowers/specs/2026-09-09-minimal-window-design.md`

## Global Constraints

- Documentation, comments and commit messages are **English**. Conversation with the author is Russian.
- `Packages/Core` carries no human-facing strings. `StatusUI` is the single exemption (`CoreHasNoHumanStringsTests.exempt`), so both new files there may hold text.
- A catalogue key that is never written as a literal in the sources fails `NoOrphanStrings`. Add a key and use it **in the same commit**.
- A new string goes into all ten catalogues through `tools/add_strings.py`; a test checks that key sets and placeholders match.
- `make test` is the gate: 548 tests in 97 suites pass before this work starts. Every task ends green.
- `make build` must still produce the app; the App layer has no unit tests, so a task that only touches `App/` is verified by building.
- Every non-obvious decision goes into `docs/DECISIONS.md` — what, why, what it cost. Append-only.
- **Another session has uncommitted work in this tree** (the `Diagnostics` module, `App/PreferencesModel.swift`, `Signing.xcconfig`, `site/index.html`, the ten catalogues). Stage files by name, never `git add -A`, and never commit a file this plan does not name.
- No personal data in anything committed. Test fixtures use `name@example.com`.

## File structure

| File | Responsibility |
|---|---|
| `Packages/Core/Sources/Preferences/Preferences.swift` | the `minimalWindow` flag, its default and its fallback decode |
| `Packages/Core/Sources/StatusUI/HeadlineWindow.swift` | **new** — which limit a one-line row shows |
| `Packages/Core/Sources/StatusUI/MinimalAccountRow.swift` | **new** — the one-line row |
| `App/PopoverView.swift` | chooses between the full window and the minimal one |
| `App/Settings/AppearancePane.swift` | the toggle, and greying out `Row layout` |
| `App/AppModel.swift` | owns `LoginController`; publishes preference changes |
| `App/Settings/AccountsPane.swift` | observes the hoisted controller instead of owning it |
| `App/StatusItemController.swift` | the three new menu items |
| `Packages/Core/Sources/StatusUI/Resources/*.lproj/Localizable.strings` | one new key, ten languages |

---

### Task 1: The preference

**Files:**
- Modify: `Packages/Core/Sources/Preferences/Preferences.swift`
- Test: `Packages/Core/Tests/PreferencesTests/PreferencesTests.swift`

**Interfaces:**
- Produces: `Preferences.minimalWindow: Bool`, default `false`.

- [ ] **Step 1: Write the failing tests**

Append to `Packages/Core/Tests/PreferencesTests/PreferencesTests.swift`:

```swift
@Test func theWindowIsFullUntilSomebodyAsksOtherwise() {
    #expect(Preferences.defaults.minimalWindow == false)
}

/// The field-by-field decoder, from the other direction: a settings file
/// written before this flag existed must keep every other answer in it.
@Test func settingsStoredBeforeTheFlagExistedSurviveTheUpgrade() throws {
    var stored = Preferences.defaults
    stored.languageCode = "ru"
    stored.thresholds = [90]
    stored.rowLayout = .rings

    let encoded = try JSONEncoder().encode(stored)
    var fields = try #require(
        try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    fields.removeValue(forKey: "minimalWindow")
    let older = try JSONSerialization.data(withJSONObject: fields)

    let read = try JSONDecoder().decode(Preferences.self, from: older)
    #expect(read.minimalWindow == false)
    #expect(read.languageCode == "ru")
    #expect(read.thresholds == [90])
    #expect(read.rowLayout == .rings)
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift test --package-path Packages/Core --filter theWindowIsFullUntilSomebodyAsksOtherwise`
Expected: FAIL — `value of type 'Preferences' has no member 'minimalWindow'`.

- [ ] **Step 3: Add the field**

In `Preferences.swift`, in the `// Appearance` block, after `showSnapshotAge`:

```swift
    /// The window stripped to a list: one line per account, no header, no
    /// dividers, no footer labels. A `Bool` rather than a two-valued enum
    /// because the settings toggle and the checked menu item say the same
    /// thing, and both can be labelled from one catalogue key.
    public var minimalWindow: Bool
```

In `Preferences.defaults`, after `showSnapshotAge: true,`:

```swift
        minimalWindow: false,
```

In `init(from:)`, after the `showSnapshotAge` line:

```swift
        minimalWindow        = read(.minimalWindow, fallback.minimalWindow)
```

- [ ] **Step 4: Run the whole package suite**

Run: `make test`
Expected: PASS, 550 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/Core/Sources/Preferences/Preferences.swift \
        Packages/Core/Tests/PreferencesTests/PreferencesTests.swift
git commit -m "A flag for the window stripped to a list"
```

---

### Task 2: Which limit the single line shows

**Files:**
- Create: `Packages/Core/Sources/StatusUI/HeadlineWindow.swift`
- Test: `Packages/Core/Tests/StatusUITests/HeadlineWindowTests.swift`

**Interfaces:**
- Consumes: `Preferences.PrimaryWindow` (`.worst`, `.session`, `.weekly`), `ProviderKit.AccountSnapshot`.
- Produces: `AccountSnapshot.headlineWindow(for: PrimaryWindow) -> LimitWindow?`.

- [ ] **Step 1: Write the failing test**

Create `Packages/Core/Tests/StatusUITests/HeadlineWindowTests.swift`:

```swift
import Testing
import Foundation
import ProviderKit
import Preferences
@testable import StatusUI

/// The one-line row shows one limit, and this is the choice of which.
///
/// It falls back rather than showing nothing: a Codex account has whatever its
/// session files gave it, and a line that vanished because the requested window
/// is missing would read as a broken account rather than as a missing window.
@Suite struct WhichLimitTheLineShows {

    private func snapshot(_ windows: [LimitWindow]) -> AccountSnapshot {
        AccountSnapshot(
            id: "claude/one", provider: .claude,
            displayName: "name@example.com", planLabel: "Max 20x",
            windows: windows,
            freshness: .live(Date(timeIntervalSince1970: 0)), failure: nil
        )
    }

    private let session = LimitWindow(id: "session", percent: 88, resetsAt: nil)
    private let weekly = LimitWindow(id: "weekly", percent: 23, resetsAt: nil)

    @Test func busiestTakesTheFullerWindow() {
        let account = snapshot([session, weekly])
        #expect(account.headlineWindow(for: .worst)?.id == "session")
    }

    @Test func askingForOneTakesThatOne() {
        let account = snapshot([session, weekly])
        #expect(account.headlineWindow(for: .weekly)?.id == "weekly")
        #expect(account.headlineWindow(for: .session)?.id == "session")
    }

    @Test func aMissingWindowFallsBackToWhatIsThere() {
        let account = snapshot([weekly])
        #expect(account.headlineWindow(for: .session)?.id == "weekly")
    }

    @Test func anAccountWithNoWindowsHasNoLine() {
        #expect(snapshot([]).headlineWindow(for: .worst) == nil)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `swift test --package-path Packages/Core --filter WhichLimitTheLineShows`
Expected: FAIL — `value of type 'AccountSnapshot' has no member 'headlineWindow'`.

- [ ] **Step 3: Write the implementation**

Create `Packages/Core/Sources/StatusUI/HeadlineWindow.swift`:

```swift
import ProviderKit
import Preferences

public extension AccountSnapshot {
    /// The limit a one-line row shows, chosen by the "Primary window" setting.
    ///
    /// It lives here rather than in `Monitoring`, which makes a similar choice
    /// *across* accounts for the menu bar label: that answers "which account is
    /// the headline", this answers "which of one account's limits is", and
    /// folding them together would tie the window's layout to the menu bar's.
    ///
    /// The fallback is deliberate. A Codex account carries whichever windows
    /// its session files described, and a row that disappeared because the
    /// requested window is absent would read as a broken account.
    func headlineWindow(for choice: PrimaryWindow) -> LimitWindow? {
        switch choice {
        case .worst:   peakWindow
        case .session: windows.first { $0.id == "session" } ?? peakWindow
        case .weekly:  windows.first { $0.id == "weekly" } ?? peakWindow
        }
    }
}
```

- [ ] **Step 4: Run the suite**

Run: `make test`
Expected: PASS, 554 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/Core/Sources/StatusUI/HeadlineWindow.swift \
        Packages/Core/Tests/StatusUITests/HeadlineWindowTests.swift
git commit -m "Choose the one limit a single-line row shows"
```

---

### Task 3: The one-line row

**Files:**
- Create: `Packages/Core/Sources/StatusUI/MinimalAccountRow.swift`

**Interfaces:**
- Consumes: `headlineWindow(for:)` from Task 2, `Localization.windowTitle/percent/remaining/failureText/spokenSummary`, `Severity.tint`.
- Produces: `MinimalAccountRow(snapshot:now:choice:showSnapshotAge:localization:)`.

No new catalogue keys: every string it says is already in the ten catalogues, used by `AccountRow`.

- [ ] **Step 1: Write the view**

Create `Packages/Core/Sources/StatusUI/MinimalAccountRow.swift`:

```swift
import SwiftUI
import ProviderKit
import Preferences

/// One account on one line: name, which limit, how full, how long left, and a
/// hairline under it.
///
/// A separate view rather than a fourth `RowLayout`. That enum describes a row;
/// the setting behind this one also takes away the window's header, its
/// dividers and its footer labels, and a single setting governing two scopes is
/// the kind nobody can predict from its name.
///
/// Colour is spent once and only when there is something to say: the bar and
/// the percentage stay grey while `Severity` is `.ok`. The service badge and
/// the plan label are not drawn at all — they are in the tooltip, which is the
/// same place this project already keeps `ProviderFailure.diagnostic`.
///
/// VoiceOver is unaffected: the row reads as the same sentence the full one
/// does, both windows included. This setting takes things off the screen, not
/// out of the app.
public struct MinimalAccountRow: View {
    private let snapshot: AccountSnapshot
    private let now: Date
    private let choice: PrimaryWindow
    private let showSnapshotAge: Bool

    @ObservedObject private var loc: Localization

    public init(
        snapshot: AccountSnapshot,
        now: Date,
        choice: PrimaryWindow,
        showSnapshotAge: Bool,
        localization: Localization
    ) {
        self.snapshot = snapshot
        self.now = now
        self.choice = choice
        self.showSnapshotAge = showSnapshotAge
        self.loc = localization
    }

    private var window: LimitWindow? { snapshot.headlineWindow(for: choice) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            line
            if snapshot.failure == nil, let window { bar(window) }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 6)
        .help(tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(loc.spokenSummary(for: snapshot, now: now))
    }

    private var line: some View {
        HStack(spacing: 6) {
            Text(snapshot.displayName)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if let failure = snapshot.failure {
                Text(loc.failureText(failure.kind))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if let window {
                if snapshot.freshness.isStale && showSnapshotAge {
                    Text(capturedDate)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Text(loc.windowTitle(window.id))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text(loc.percent(window.percent))
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(paint(window))
                Text(loc.remaining(window.remaining(from: now)))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    // Wide enough for "5 d 23 h" in the language that spells it
                    // longest, so the percentage beside it does not shuffle
                    // sideways every time a countdown changes unit.
                    .frame(width: 58, alignment: .trailing)
            }
        }
    }

    /// Grey until it matters. `LimitBar` is not reused: it paints every
    /// percentage, which is right in the full window and is the one habit this
    /// window exists to drop.
    private func bar(_ window: LimitWindow) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(paint(window))
                    .frame(width: max(2, geo.size.width * window.percent / 100))
            }
        }
        .frame(height: 2)
    }

    private func paint(_ window: LimitWindow) -> AnyShapeStyle {
        window.severity == .ok
            ? AnyShapeStyle(.tertiary)
            : AnyShapeStyle(window.severity.tint)
    }

    /// Everything the row stopped drawing, in one tooltip: the service and the
    /// plan always, when the reading was taken if it is old, and the log's own
    /// sentence when there is a failure.
    private var tooltip: String {
        var parts = ["\(snapshot.provider.title) · \(snapshot.planLabel)"]
        if snapshot.freshness.isStale {
            parts.append(String(format: loc("Data from %@"), capturedDate))
        }
        if let failure = snapshot.failure, !failure.diagnostic.isEmpty {
            parts.append(failure.diagnostic)
        }
        return parts.joined(separator: "\n")
    }

    private var capturedDate: String {
        let captured = snapshot.freshness.capturedAt
        guard captured > .distantPast else { return loc("no data") }
        let formatter = DateFormatter()
        formatter.locale = loc.activeLocale
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: captured)
    }
}
```

- [ ] **Step 2: Build the package and run the suite**

Run: `make test`
Expected: PASS. The guards that could object are `CoreHasNoHumanStrings` (`StatusUI` is exempt), `NoOrphanStrings` (no new keys, and `"Data from %@"` and `"no data"` were already used by `AccountRow`) and `OneRowDrawnEverywhere` (it looks for `struct AccountRow: View`, which this file does not contain).

- [ ] **Step 3: Commit**

```bash
git add Packages/Core/Sources/StatusUI/MinimalAccountRow.swift
git commit -m "One account on one line, grey until it matters"
```

---

### Task 4: The window that draws it

**Files:**
- Modify: `App/PopoverView.swift`

**Interfaces:**
- Consumes: `Preferences.minimalWindow`, `MinimalAccountRow`.
- Produces: nothing other tasks read.

- [ ] **Step 1: Split the body in two**

Replace the `body` in `App/PopoverView.swift` with:

```swift
    var body: some View {
        Group {
            if model.preferences.minimalWindow { minimal } else { full }
        }
        .frame(width: 322)
        // The chosen language decides how a date and a time are written, not
        // only which words are used. Left alone, SwiftUI formats them in the
        // system's language while every label around them follows the setting —
        // so the badge said `28 Aug` in one language and the clock beside it
        // read in another.
        .environment(\.locale, loc.activeLocale)
        .environment(\.layoutDirection, loc.layoutDirection ?? .leftToRight)
        .id(loc.language)
        .onAppear { model.isPopoverOpen = true }
        .onDisappear { model.isPopoverOpen = false }
        .onReceive(tick) { now = $0 }
    }

    /// The window as it has always been: a heading, two meters per account,
    /// three named buttons.
    private var full: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)

            if model.snapshots.isEmpty {
                empty
            } else {
                ForEach(Array(model.snapshots.enumerated()), id: \.element.id) { index, snapshot in
                    AccountRow(
                        snapshot: snapshot, now: now,
                        layout: model.preferences.rowLayout,
                        showSnapshotAge: model.preferences.showSnapshotAge,
                        localization: loc
                    )
                    if index < model.snapshots.count - 1 { Divider().opacity(0.35) }
                }
            }

            Divider().opacity(0.5)
            footer
        }
    }

    /// The same window with everything that is not a reading taken off it.
    ///
    /// Nothing is drawn above the list unless the readings are overdue, and
    /// that line is the only place this window spends a heading: a clock
    /// showing when a current reading was taken answers a question nobody
    /// asked, while `2 h old` answers the one that matters.
    private var minimal: some View {
        VStack(spacing: 0) {
            if case .overdue(let seconds) = readingAge {
                Text(String(format: loc("%@ old"), loc.remaining(seconds)))
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(Severity.hot.tint)
                    .help(loc("Nothing has been read for a while. A sign-in prompt may be waiting."))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 13)
                    .padding(.bottom, 2)
            }

            if model.snapshots.isEmpty {
                empty
            } else {
                ForEach(model.snapshots) { snapshot in
                    MinimalAccountRow(
                        snapshot: snapshot, now: now,
                        choice: model.preferences.primaryWindow,
                        showSnapshotAge: model.preferences.showSnapshotAge,
                        localization: loc
                    )
                }
            }

            quietFooter
        }
        .padding(.vertical, 8)
    }
```

- [ ] **Step 2: Give the age its own property**

`freshness` computes the age inline and the minimal window needs the same answer. Above `freshness`, add:

```swift
    /// How old the readings are, and whether that is older than the polling
    /// interval says it should be. Both windows ask.
    private var readingAge: ReadingAge {
        readingAge(
            lastUpdated: model.lastUpdated, now: now,
            pollingEvery: model.preferences.backgroundInterval
        )
    }
```

and in `freshness` replace the `let age = readingAge(...)` binding with `let age = readingAge`.

If the type returned by the free function `readingAge(lastUpdated:now:pollingEvery:)` is not named `ReadingAge`, use the name it actually declares — find it with:

```bash
grep -rn "func readingAge" Packages/Core/Sources
```

- [ ] **Step 3: Add the quiet footer**

Below `footer`, add:

```swift
    /// Three symbols where the full window has three words. The actions are in
    /// the status item's menu as well, but a window whose only way out is a
    /// gesture nothing advertises is a window with no way out.
    private var quietFooter: some View {
        HStack {
            quietButton("arrow.clockwise", loc("Refresh"), "r") {
                Task { await model.refresh(.person) }
            }
            Spacer()
            quietButton("gearshape", loc("Settings…"), ",") { SettingsWindow.open() }
            Spacer()
            quietButton("power", loc("Quit"), "q") { NSApplication.shared.terminate(nil) }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
    }

    private func quietButton(
        _ symbol: String, _ title: String, _ key: KeyEquivalent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tertiary)
        .help(title)
        .accessibilityLabel(title)
        .keyboardShortcut(key)
    }
```

- [ ] **Step 4: Publish preference changes**

`AppModel.preferences` is a plain `var` with a `didSet`, so assigning it does not tell SwiftUI anything, and a window that is rebuilt from it can show the layout that was chosen before last. In `App/AppModel.swift`, add as the first line of that `didSet`:

```swift
            // A plain `var` on an `ObservableObject` publishes nothing, and
            // this one decides what the window draws. Assignments are rare —
            // a person changing a setting, the update check stamping its
            // moment — so telling the views about all of them is cheaper than
            // reasoning about which ones matter.
            objectWillChange.send()
```

- [ ] **Step 5: Build**

Run: `make build`
Expected: build succeeds.

- [ ] **Step 6: Look at it**

Run: `make run`, then flip the flag by hand — settings are in `~/Library/Preferences/app.softcap.Softcap.plist`; the toggle in the interface arrives in Task 5, so for now:

```bash
defaults write app.softcap.Softcap minimalWindow -bool true
```

Expected: opening the window shows one line per account, a hairline under each, three symbols at the foot, and no heading. **Check the height** — this is the risk the spec names: if `NSPopover` keeps the old height, `makePopover()` in `App/StatusItemController.swift` needs `popover.contentSize` set from the hosting controller's fitting size. Write down which it was; it goes in the decision log in Task 8.

Put it back afterwards:

```bash
defaults delete app.softcap.Softcap minimalWindow
```

- [ ] **Step 7: Commit**

```bash
git add App/PopoverView.swift App/AppModel.swift
git commit -m "Draw the window as a list when the flag is set"
```

---

### Task 5: The toggle in settings

**Files:**
- Modify: `App/Settings/AppearancePane.swift`
- Modify: `Packages/Core/Sources/StatusUI/Resources/*.lproj/Localizable.strings` (all ten, through the tool)

**Interfaces:**
- Consumes: `Preferences.minimalWindow`.
- Produces: the catalogue key `Minimal window`.

- [ ] **Step 1: Add the key to all ten catalogues**

Run from the repository root:

```bash
python3 tools/add_strings.py <<'JSON'
{
  "Minimal window": {
    "zh-Hans": "极简窗口",
    "hi": "न्यूनतम विंडो",
    "es": "Ventana mínima",
    "ar": "نافذة مبسطة",
    "fr": "Fenêtre minimale",
    "bn": "সংক্ষিপ্ত উইন্ডো",
    "pt-BR": "Janela mínima",
    "ru": "Минимальное окно",
    "id": "Jendela minimal"
  }
}
JSON
```

- [ ] **Step 2: Run the suite and watch `NoOrphanStrings` fail**

Run: `make test`
Expected: FAIL — `in all ten catalogues and used nowhere: ["Minimal window"]`. This is the guard doing its job; the next step is what clears it.

- [ ] **Step 3: Use the key**

In `App/Settings/AppearancePane.swift`, between the `Primary window` picker and the `Row layout` picker:

```swift
                Toggle(loc("Minimal window"), isOn: binding(\.minimalWindow))
```

and give the `Row layout` picker a reason to be grey — replace it with:

```swift
                Picker(loc("Row layout"), selection: binding(\.rowLayout)) {
                    ForEach(RowLayout.allCases, id: \.self) { Text(loc.title($0)).tag($0) }
                }
                // A row layout describes the full window, and the minimal one
                // does not have one. Disabled rather than hidden: a setting
                // that vanishes reads as a bug, a grey one explains itself.
                .disabled(model.value.minimalWindow)
```

- [ ] **Step 4: Run the suite**

Run: `make test`
Expected: PASS, 554 tests.

- [ ] **Step 5: Build and look**

Run: `make build && make run`
Expected: Appearance holds a "Minimal window" toggle; turning it on greys out "Row layout" and the next opening of the window is the list.

- [ ] **Step 6: Commit**

```bash
git add App/Settings/AppearancePane.swift \
        Packages/Core/Sources/StatusUI/Resources/en.lproj/Localizable.strings \
        Packages/Core/Sources/StatusUI/Resources/zh-Hans.lproj/Localizable.strings \
        Packages/Core/Sources/StatusUI/Resources/hi.lproj/Localizable.strings \
        Packages/Core/Sources/StatusUI/Resources/es.lproj/Localizable.strings \
        Packages/Core/Sources/StatusUI/Resources/ar.lproj/Localizable.strings \
        Packages/Core/Sources/StatusUI/Resources/fr.lproj/Localizable.strings \
        Packages/Core/Sources/StatusUI/Resources/bn.lproj/Localizable.strings \
        Packages/Core/Sources/StatusUI/Resources/pt-BR.lproj/Localizable.strings \
        Packages/Core/Sources/StatusUI/Resources/ru.lproj/Localizable.strings \
        Packages/Core/Sources/StatusUI/Resources/id.lproj/Localizable.strings
git commit -m "Offer the minimal window in settings"
```

**Note:** the ten catalogues carry another session's uncommitted additions. Before committing, check `git diff --cached` and drop any hunk that is not the `Minimal window` line — `git restore --staged` the file and stage it with `git add -p` instead.

---

### Task 6: The sign-in outlives the pane

**Files:**
- Modify: `App/AppModel.swift`
- Modify: `App/Settings/AccountsPane.swift`

**Interfaces:**
- Produces: `AppModel.login: LoginController`, reachable from anywhere the model is.

- [ ] **Step 1: Give the model the controller**

In `App/AppModel.swift`, beside `let store: CredentialStore`:

```swift
    /// The browser sign-in.
    ///
    /// It used to be a `@StateObject` inside the Accounts pane, which made it
    /// unreachable from the menu and no longer than the pane: leaving that
    /// section during a sign-in destroyed the controller and the sign-in with
    /// it. Lazy, so a launch that never signs anybody in never builds one.
    lazy var login = LoginController(store: store)
```

- [ ] **Step 2: Have the pane observe it**

In `App/Settings/AccountsPane.swift`, replace

```swift
    @StateObject private var loginController: LoginController
```

with

```swift
    @ObservedObject private var loginController: LoginController
```

and in `init(model:appModel:)` replace

```swift
        _loginController = StateObject(wrappedValue: LoginController(store: appModel.store))
```

with

```swift
        loginController = appModel.login
```

Nothing else in the pane changes: it calls `loginController.start()`, `.cancel()`, and reads `.isRunning`, `.manualCodeExpected`, `.message` and `.completedSignIns` exactly as before.

- [ ] **Step 3: Build**

Run: `make build`
Expected: build succeeds.

- [ ] **Step 4: Prove the fix by hand**

Run: `make run`, open Settings → Accounts, press "Add account…", and while the browser is waiting switch to another section and back.
Expected: the spinner and "Cancel" are still there, and the sign-in still completes. Before this change the controller was gone and the flow was dead.

- [ ] **Step 5: Commit**

```bash
git add App/AppModel.swift App/Settings/AccountsPane.swift
git commit -m "Let a sign-in outlive the pane that started it"
```

---

### Task 7: The menu

**Files:**
- Modify: `App/StatusItemController.swift`

**Interfaces:**
- Consumes: `AppModel.login` (Task 6), `Preferences.minimalWindow` (Task 1), the existing catalogue keys `Add account…` and `Statistics`.

- [ ] **Step 1: Add the three items**

In `showMenu(from:)`, after the `settings` item is added and before the `update` item:

```swift
        let addAccount = NSMenuItem(
            title: Localization.shared("Add account…"),
            action: #selector(addAccount), keyEquivalent: ""
        )
        addAccount.target = self
        menu.addItem(addAccount)

        let statistics = NSMenuItem(
            title: Localization.shared("Statistics") + "…",
            action: #selector(openStatistics), keyEquivalent: ""
        )
        statistics.target = self
        menu.addItem(statistics)

        menu.addItem(.separator())

        // The one setting with a home outside settings. It is the whole shape
        // of the window, it is flipped often enough to want reaching, and a
        // checked item says the current state without being asked.
        let minimal = NSMenuItem(
            title: Localization.shared("Minimal window"),
            action: #selector(toggleMinimalWindow), keyEquivalent: ""
        )
        minimal.target = self
        minimal.state = preferences.value.minimalWindow ? .on : .off
        menu.addItem(minimal)
```

- [ ] **Step 2: Add the three actions**

Beside `openUpdates()`:

```swift
    /// Opens the Accounts section and starts the browser sign-in.
    ///
    /// Both, not just the second: a sign-in can come back asking for a code
    /// pasted by hand, and the field that takes it is on that screen. Starting
    /// one with nothing on screen would strand anybody it asked.
    @objc private func addAccount() {
        model.settingsSection = .accounts
        SettingsWindow.open()
        model.login.start()
    }

    @objc private func openStatistics() {
        model.settingsSection = .statistics
        SettingsWindow.open()
    }

    @objc private func toggleMinimalWindow() {
        preferences.update { $0.minimalWindow.toggle() }
    }
```

- [ ] **Step 3: Build**

Run: `make build`
Expected: build succeeds.

- [ ] **Step 4: Look at the menu**

Run: `make run`, right-click the status item.
Expected: version, Refresh, Settings…, Add account…, Statistics…, a checked-or-not "Minimal window", the update item, Quit. Ticking "Minimal window" and opening the window shows the list; the tick reflects the settings toggle and the settings toggle reflects the tick.

- [ ] **Step 5: Commit**

```bash
git add App/StatusItemController.swift
git commit -m "Put the window's shape, a sign-in and the chart in the menu"
```

---

### Task 8: The record

**Files:**
- Modify: `docs/DECISIONS.md`
- Modify: `README.md`

- [ ] **Step 1: Write the decision entry**

Append to `docs/DECISIONS.md`, following the house shape — heading dated today, then **Decision**, **Why**, **Cost**:

```markdown
---

## 2026-09-09 · A setting that strips the window to a list

**Decision.** `minimalWindow` draws one line per account — name, which limit,
how full, how long left, a hairline bar — with no heading, no dividers, no
service badge, no plan label, and colour only above `Severity.ok`. It is a
`Bool`, it is off by default, and it is reachable from the status item's menu
as well as from Appearance.

**Why.** The full window is built for the reading somebody opens the app to do,
and most openings are not that: they are a glance to confirm nothing is on
fire, and for those it says nine things where one would do. Both readings are
legitimate, so this is a setting rather than a new design.

A `Bool` rather than a two-valued enum because the toggle and the checked menu
item say the same thing, and one catalogue key labels both — an enum would have
cost four keys in ten languages to say it.

`MinimalAccountRow` is a second view rather than a fourth `RowLayout`: that
enum describes a row, and this setting also takes away the window around it.

**Cost.** A second row view to keep in step with the first — the guard that
holds the four surfaces to one shared row does not cover it, because it is
about the window and not about the account. `Primary window` now has two jobs:
the menu bar label and this row's one limit. The badge and the plan label are
only in the tooltip here.
```

If Task 4 found that `NSPopover` needed its `contentSize` set by hand, add a fourth paragraph saying so; if it resized on its own, say that instead — the spec names it as an open question and the log is where questions get closed.

- [ ] **Step 2: Say it in the README**

In `README.md`, in the `## Settings` section, after the `**Appearance** — system, light or dark.` line:

```markdown
**Minimal window** — the limits window as a list: one line per account, and
colour only where a limit is close. The heading and the named buttons go; the
three actions stay as symbols, and everything else the row was saying moves
into its tooltip. Off by default, and in the status item's menu as well as in
settings.
```

- [ ] **Step 3: Run everything**

Run: `make test && make build`
Expected: 554 tests pass and the app builds. `ReadmeQuotesTheCode` reads the README against the code, so a claim written here that the code does not support fails the suite.

- [ ] **Step 4: Commit**

```bash
git add docs/DECISIONS.md README.md
git commit -m "Record the minimal window, and say so in the README"
```

---

## Self-review

**Spec coverage.** The setting and its decoding — Task 1. Choosing the window —
Task 2. The row, its colour, its tooltip, its stale mark and its failure line —
Task 3. The window: the overdue line, the missing header, the empty state, the
icon footer — Task 4. The toggle and the greyed `Row layout` — Task 5. The
`LoginController` hoist the spec asks for — Task 6. The three menu items —
Task 7. The decision log and the README — Task 8. The spec's "known risk" is
checked in Task 4 Step 6 and recorded in Task 8 Step 1. The spec's "what does
not change" needs no task: no task touches `Widget/`, `iOS/`, `iOSWidget/` or
`SharedSnapshot`.

**Consistency.** `headlineWindow(for:)` is defined in Task 2 and called in
Task 3 with the same signature. `MinimalAccountRow`'s five arguments in Task 3
are the five passed in Task 4. `AppModel.login` is created in Task 6 and used
in Tasks 6 and 7. `preferences.update {}` in Task 7 is `PreferencesModel`'s
existing method.

**One refinement on the spec.** The menu's "Add account…" opens the Accounts
section *and* starts the sign-in, rather than only starting it: the manual-code
field lives on that screen, and a sign-in that asks for a code with nothing on
screen would strand whoever pressed it.
