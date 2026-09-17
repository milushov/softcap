# Minimal Window Period Peek Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The `5h`/`week` label in a minimal-window row becomes a click-to-peek toggle between the row's two periods, and the peek is forgotten whenever the window closes.

**Architecture:** Two pure members beside `headlineWindow(for:)` decide what a click shows and whether a row has anything to peek at; `MinimalAccountRow` holds the peek as `@State`, resolves its window through `peek ?? choice`, and clears it in `onDisappear`. Nothing outside the row changes.

**Tech Stack:** Swift 6 / SwiftUI, Swift Testing (`@Suite`/`@Test`/`#expect`), SwiftPM package `Packages/Core`, `make test` / `make build`.

**Spec:** `docs/superpowers/specs/2026-09-17-minimal-window-period-peek-design.md`

## Global Constraints

- The repository is public: no personal data, machine names, absolute home paths, or credentials in any file or commit message.
- Commit messages carry no agent trailers, no session links, no `Co-Authored-By: Claude` — plain messages in the author's voice, ending on the last line of real content.
- No `import AppKit` anywhere in `Packages/Core` (enforced by `CoreStaysPortable`); the package builds for macOS 14 and iOS 17.
- No new human-facing string literals in Core; labels come only through `Localization` keys that already exist (`5h`, `week` via `windowTitle(_:)`). No catalogue changes.
- `Preferences`, `AppModel`, `PopoverView` are not modified.
- All documentation in English.
- Never `rm`; quarantine with `~/.claude/bin/ctrash` if a file must go.
- Tests run from the repo root with `make test` (runs `swift test` inside `Packages/Core`); the full suite currently passes at 604 tests and must stay green.

---

### Task 1: Pure logic — `peekChoice` and `hasAnotherPeriod`

**Files:**
- Modify: `Packages/Core/Sources/StatusUI/HeadlineWindow.swift`
- Test: `Packages/Core/Tests/StatusUITests/HeadlineWindowTests.swift`

**Interfaces:**
- Consumes: `AccountSnapshot.headlineWindow(for:)` (already in `HeadlineWindow.swift`), `LimitWindow(id:percent:resetsAt:)` from `ProviderKit`, `PrimaryWindow` from `Preferences`.
- Produces: `LimitWindow.peekChoice: PrimaryWindow` (public) and `AccountSnapshot.hasAnotherPeriod: Bool` (public) — Task 2's view code and scan tests use these exact names.

- [ ] **Step 1: Write the failing tests**

Append to `Packages/Core/Tests/StatusUITests/HeadlineWindowTests.swift` (after the existing `WhichLimitTheLineShows` suite):

```swift
/// A click on the period label shows the row's other window, and only rows
/// that really have another window get the click at all.
@Suite struct PeekingAtTheOtherPeriod {

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

    @Test func theClickShowsTheOtherPeriod() {
        #expect(session.peekChoice == .weekly)
        #expect(weekly.peekChoice == .session)
    }

    @Test func twoPeriodsAreWorthAClick() {
        #expect(snapshot([session, weekly]).hasAnotherPeriod)
    }

    @Test func oneWindowHasNothingElseToShow() {
        #expect(!snapshot([session]).hasAnotherPeriod)
        #expect(!snapshot([weekly]).hasAnotherPeriod)
    }

    @Test func noWindowsHaveNothingToShowEither() {
        #expect(!snapshot([]).hasAnotherPeriod)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd Packages/Core && swift test --filter PeekingAtTheOtherPeriod`
Expected: compile error — `peekChoice` and `hasAnotherPeriod` do not exist yet.

- [ ] **Step 3: Implement the two members**

Append to `Packages/Core/Sources/StatusUI/HeadlineWindow.swift`:

```swift
public extension LimitWindow {
    /// The choice that shows the other period than this window.
    ///
    /// Two branches, not three: window identifiers are a closed set —
    /// `Models.swift` names `session` and `weekly`, and both providers
    /// normalise to them.
    var peekChoice: PrimaryWindow { id == "session" ? .weekly : .session }
}

public extension AccountSnapshot {
    /// Whether a row has another period to peek at: the two choices resolve
    /// to different windows. One-window accounts fall back to the same
    /// window under either choice and answer no, so the label above them
    /// stays plain text rather than a button that changes nothing.
    var hasAnotherPeriod: Bool {
        headlineWindow(for: .session)?.id != headlineWindow(for: .weekly)?.id
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd Packages/Core && swift test --filter PeekingAtTheOtherPeriod`
Expected: 4 tests pass. Also run `swift test --filter WhichLimitTheLineShows` — the 4 existing tests stay green.

---

### Task 2: The view — peek state, the label button, and the scan suite that pins it

**Files:**
- Modify: `Packages/Core/Sources/StatusUI/MinimalAccountRow.swift`
- Create: `Packages/Core/Tests/StatusUITests/ThePeekIsNotRememberedTests.swift`

**Interfaces:**
- Consumes: `LimitWindow.peekChoice` and `AccountSnapshot.hasAnotherPeriod` from Task 1, exact names.
- Produces: nothing later tasks call; the row's public `init` is unchanged, so `PopoverView` recompiles as is.

- [ ] **Step 1: Write the failing scan suite**

Create `Packages/Core/Tests/StatusUITests/ThePeekIsNotRememberedTests.swift`. It reads the view's source, in the idiom of `TheWindowCanFixASignIn`: these are views, a scan cannot prove a screen behaves, but it can prove the claim is still written.

```swift
import Testing
import Foundation

/// The minimal row can show its other period on a click, and the click is
/// deliberately worth nothing tomorrow: the peek lives in the view, dies with
/// the window, and is written to no store.
///
/// Scanned out of the source for the reason `TheWindowCanFixASignIn` gives:
/// these are views, the package tests are the only tests this project has,
/// and a scan cannot prove a screen behaves — it can prove the claim is
/// still written.
@Suite struct ThePeekIsNotRemembered {

    /// View-local state, not a preference. The one declaration that makes
    /// the peek forgettable at all.
    @Test func thePeekIsStateOfTheView() throws {
        #expect(try Self.row(contains: "@State private var peek: PrimaryWindow?"), """
            the peek is no longer view-local `@State` — held anywhere else it \
            would outlive the window, and the next opening would not show what \
            the Primary window setting says
            """)
    }

    /// The reset is what "not remembered" means in a popover that is cached:
    /// the SwiftUI tree survives between openings, so forgetting is explicit.
    @Test func closingTheWindowForgetsThePeek() throws {
        #expect(try Self.row(contains: "onDisappear { peek = nil }"), """
            the row no longer clears the peek when the window closes — the \
            popover is cached, so without this line a peek would be remembered \
            by accident and reopening would not show the default
            """)
    }

    /// The peek outranks the setting only while it exists.
    @Test func theRowResolvesThePeekOverTheSetting() throws {
        #expect(try Self.row(contains: "headlineWindow(for: peek ?? choice)"), """
            the row no longer resolves its window through `peek ?? choice` — \
            either the click shows nothing, or the setting stopped being the \
            default
            """)
    }

    /// A button that changes nothing is a broken button, so a one-window
    /// account keeps its plain text.
    @Test func onlyARowWithTwoPeriodsGetsTheButton() throws {
        #expect(try Self.row(contains: "hasAnotherPeriod"), """
            the row no longer asks whether there is another period before \
            drawing the button — a Codex account with one window would get a \
            click that does nothing
            """)
    }

    /// Nothing writes the peek anywhere. The negative half of "not stored".
    @Test func thePeekReachesNoStore() throws {
        for forbidden in ["UserDefaults", "PreferencesStore"] {
            #expect(try !Self.row(contains: forbidden), """
                the row now mentions \(forbidden) — the peek is designed to be \
                stored nowhere, and the row had no business with a store before
                """)
        }
    }

    private static func row(contains phrase: String) throws -> Bool {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // …/Tests/StatusUITests
            .deletingLastPathComponent()      // …/Tests
            .deletingLastPathComponent()      // …/Core
            .appendingPathComponent("Sources/StatusUI/MinimalAccountRow.swift")
        return try String(contentsOf: url, encoding: .utf8).contains(phrase)
    }
}
```

- [ ] **Step 2: Run the scan suite to verify it fails**

Run: `cd Packages/Core && swift test --filter ThePeekIsNotRemembered`
Expected: 4 of 5 tests FAIL (`thePeekReachesNoStore` passes vacuously — the row mentions no store today either).

- [ ] **Step 3: Change the view**

In `Packages/Core/Sources/StatusUI/MinimalAccountRow.swift`:

3a. Add two `@State` properties after the `loc` property (after the line `@ObservedObject private var loc: Localization`):

```swift
    /// A click on the period label, and nothing longer-lived than that. `nil`
    /// obeys the `Primary window` setting; `.session`/`.weekly` is somebody
    /// peeking at the row's other period. Deliberately not a preference:
    /// remembering it would quietly turn one curious click into a changed
    /// default, so the window forgets it on closing — explicitly, in
    /// `onDisappear`, because the popover is cached and this view's state
    /// survives between openings.
    @State private var peek: PrimaryWindow?

    /// Whether the pointer is over the period label. Hover is the affordance
    /// that the label is clickable — underlining, not a cursor: `NSCursor` is
    /// AppKit, which `CoreStaysPortable` bans from this package absolutely.
    @State private var hoveringPeriod = false
```

3b. Change the `window` computed property from

```swift
    private var window: LimitWindow? { snapshot.headlineWindow(for: choice) }
```

to

```swift
    private var window: LimitWindow? { snapshot.headlineWindow(for: peek ?? choice) }
```

3c. In `body`, add the reset alongside the existing modifiers — after `.help(tooltip)`:

```swift
        .help(tooltip)
        .onDisappear { peek = nil }
```

3d. In `line`, replace the period label

```swift
                Text(loc.windowTitle(window.id))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
```

with

```swift
                periodLabel(window)
```

3e. Add the label builder after the `line` property:

```swift
    /// The period label, clickable when the row has another period to show.
    ///
    /// The click flips only its own row — with `Busiest` the rows' labels
    /// already differ, so a whole-window flip would have no honest meaning.
    /// The percentage, the remaining time and the bar all follow, because
    /// every one of them is computed from the single `window` this row
    /// resolves. VoiceOver is deliberately untouched: the row collapses into
    /// `spokenSummary`, which already reads both periods, so the click
    /// reveals nothing a listener was missing.
    @ViewBuilder
    private func periodLabel(_ window: LimitWindow) -> some View {
        if snapshot.hasAnotherPeriod {
            Button { peek = window.peekChoice } label: {
                periodText(window, underlined: hoveringPeriod)
            }
            .buttonStyle(.plain)
            // The same line `SignInPrompt` and `quietButton` carry, for the
            // same reason: the first button in the popover otherwise opens
            // wearing the accent-coloured focus fill.
            .focusEffectDisabled()
            .onHover { hoveringPeriod = $0 }
        } else {
            periodText(window)
        }
    }

    private func periodText(_ window: LimitWindow, underlined: Bool = false) -> some View {
        Text(loc.windowTitle(window.id))
            .underline(underlined)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
    }
```

- [ ] **Step 4: Run the scan suite to verify it passes**

Run: `cd Packages/Core && swift test --filter ThePeekIsNotRemembered`
Expected: 5 tests PASS.

- [ ] **Step 5: Run the whole package**

Run: `make test` (repo root)
Expected: everything green — 604 existing tests plus the 9 new ones (4 logic, 5 scan). `CoreHasNoHumanStrings`, `CoreStaysPortable`, `SentencesReadAsSentences` and the localisation suites all see the new code.

---

### Task 3: Prove the app builds, log the decision, commit

**Files:**
- Modify: `docs/DECISIONS.md` (append one entry; the file already carries uncommitted text from earlier work — do not stage it)
- Commit: the two source files, the two test files, the spec, this plan.

**Interfaces:**
- Consumes: everything above; no new symbols.
- Produces: a commit on `main`.

- [ ] **Step 1: Build the app target**

Run: `make build` (repo root)
Expected: `BUILD SUCCEEDED` — `PopoverView` compiles unchanged against the row's unchanged `init`.

- [ ] **Step 2: Append the decision**

Append to `docs/DECISIONS.md`, matching the file's entry format (a dated heading in the style of the entries around it, then what/why/cost prose):

```markdown
## 2026-09-17 — the minimal window peeks, and the peek is forgotten

The period label in a minimal row — `5h` or `week` — is a button now. A click
shows the same row's other period; closing the window forgets every peek, and
the next opening obeys the `Primary window` setting as if nothing happened.

Per row rather than per window, because with `Busiest` the rows' labels
already differ and a whole-window flip has no honest meaning. Stored nowhere,
because a remembered peek is a changed default made without saying so — the
setting would stop meaning what the settings screen claims. The forgetting is
explicit: the popover is cached, the view's state survives between openings,
and `onDisappear` is what "not remembered" costs in code.

**Cost.** One more thing the row does that a screenshot cannot show; the
affordance is an underline on hover, found only by pointing at it. A one-line
scan suite (`ThePeekIsNotRemembered`) now pins the ephemerality, which is one
more test to keep honest. VoiceOver spends nothing: the row's sentence
already reads both periods.
```

- [ ] **Step 3: Commit only this feature's files**

```bash
# from the repository root
git add Packages/Core/Sources/StatusUI/HeadlineWindow.swift \
        Packages/Core/Sources/StatusUI/MinimalAccountRow.swift \
        Packages/Core/Tests/StatusUITests/HeadlineWindowTests.swift \
        Packages/Core/Tests/StatusUITests/ThePeekIsNotRememberedTests.swift \
        docs/superpowers/specs/2026-09-17-minimal-window-period-peek-design.md \
        docs/superpowers/plans/2026-09-17-minimal-window-period-peek.md
git commit -m "Let a minimal row peek at its other period

The 5h/week label is a button now: a click shows the same row's other
window, a second click goes back, and closing the popover forgets every
peek — the Primary window setting stays the only remembered choice, and
every opening starts from it.

Only rows with two distinguishable windows get the button; a one-window
account keeps plain text rather than a click that changes nothing. The
percentage, countdown and bar follow the peek because they were already
computed from the one window the row resolves. No new strings, no AppKit,
no Preferences field; VoiceOver already read both periods and is untouched."
```

Do NOT stage `docs/DECISIONS.md` (it carries the previous feature's uncommitted entry) and do not touch the other modified files in the tree — they belong to the account-recovery work awaiting its own commit. Do not push.

- [ ] **Step 4: Verify the tree**

Run: `git status && git log -1 --stat`
Expected: the commit contains exactly the six files above; `DECISIONS.md` and the account-recovery files remain modified-but-uncommitted, as they were.
