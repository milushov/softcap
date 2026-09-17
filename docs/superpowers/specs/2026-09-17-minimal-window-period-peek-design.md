# Peeking at the other period in the minimal window

The period label in a minimal row — `5h` or `week` — becomes clickable. A click
shows the same row's other period: the five-hour window where the weekly one
was showing, the weekly where the five-hour was. Clicking again goes back.
Closing the window forgets every peek; the next opening shows what the
`Primary window` setting says, exactly as today.

## Why a peek and not a setting

The window already has logic deciding which period a row leads with —
`headlineWindow(for:)`, driven by `Primary window`, whose default `Busiest`
picks whichever limit is fuller. That logic answers the common case well and
stays the answer on every opening. What it cannot answer is the glance-length
question "and how is the *other* one doing?" — which today costs a trip to
Settings and a second trip back.

So the peek is deliberately ephemeral, per row, and stored nowhere. It is a
look, not a preference: remembering it would quietly turn one curious click
into a changed default, and the row would stop matching what the setting
promises. The state dies with the window.

## The interaction

- The label is a `Button` with `.buttonStyle(.plain)`, keeping today's
  typography (10 pt, `.secondary`). `.focusEffectDisabled()` for the reason
  `SignInPrompt` and `quietButton` already give: the first button in the
  popover otherwise opens wearing the accent-coloured focus fill.
- Hovering underlines the label — the affordance that text is clickable —
  via `.onHover` and `.underline(_:)`, both pure SwiftUI. AppKit and
  `NSCursor` are unavailable here: `CoreStaysPortable` bans them from Core
  absolutely, and this module also builds for the phone.
- A click flips only its own row. Rows are independent; with `Busiest` their
  labels already differ, so a whole-window flip would have no honest meaning.
- The button exists only when the account has two distinguishable periods.
  A Codex account carrying a single window falls back to it under either
  choice; a click that changes nothing is a broken button, so such a row keeps
  the plain text it has now. A failure row keeps showing the failure — the
  label is not drawn there at all, today and after.
- The percentage, the remaining time and the hairline bar all follow the
  peek: every one of them is already computed from the single `window`
  value the row resolves, so they cannot fall out of step with the label.

## How it is forgotten

`MinimalAccountRow` gains one piece of view-local state:

    @State private var peek: PrimaryWindow?     // nil: obey the setting

The row resolves `headlineWindow(for: peek ?? choice)`. A click sets `peek`
to the choice that shows the other period; `.onDisappear` sets it back to
`nil`.

`onDisappear` is the working end of "not remembered". The popover is cached —
`togglePopover` reuses `self.popover ?? makePopover()` — so the SwiftUI tree
and its `@State` survive between openings, and without an explicit reset the
peek would be remembered by accident. Closing the popover removes the content
view from its window, which fires `onDisappear`; `PopoverView`'s own history
proves these callbacks fire here (its open-flag comment describes their exact
ordering during a language change). Changing the language while the window is
open rebuilds the subtree under `.id(loc.language)` and drops any peek with
it — acceptable for a state whose whole design is to be droppable.

Nothing else holds the state. `Preferences` gains no field, `AppModel` gains
no property, `PopoverView` passes `model.preferences.primaryWindow` exactly
as it does now.

## The pure logic

Two small members beside `headlineWindow(for:)` in `HeadlineWindow.swift`,
tested without a view:

    public extension LimitWindow {
        /// The choice that shows the other period than this window.
        var peekChoice: PrimaryWindow { id == "session" ? .weekly : .session }
    }

    public extension AccountSnapshot {
        /// Whether a row has another period to peek at: the two choices
        /// resolve to different windows. One-window accounts and empty
        /// accounts answer no.
        var hasAnotherPeriod: Bool {
            headlineWindow(for: .session)?.id != headlineWindow(for: .weekly)?.id
        }
    }

Window identifiers are a closed set — `Models.swift` documents `session` and
`weekly`, and both providers normalise to them — so `peekChoice` needs no
third branch.

## Accessibility

Unchanged, on purpose. The row collapses into one spoken element whose
sentence — `spokenSummary` — already reads **every** window the account has,
both periods included. The click exists to reveal what the screen hides, and
VoiceOver hides nothing, so there is no action to add and no new phrase to
translate.

## Strings

None. The labels come from the existing `5h` and `week` keys through
`windowTitle(_:)`; no catalogue changes in any of the ten languages.

## Tests

- `HeadlineWindowTests`: `peekChoice` flips session to weekly and weekly to
  session; `hasAnotherPeriod` is true with both windows, false with one
  (either one), false with none.
- A new scan suite in the idiom of `TheWindowCanFixASignIn`, pinning the
  claims a view test cannot reach: the peek is `@State` in
  `MinimalAccountRow` (view-local, never a preference), `onDisappear` clears
  it, and the label button asks `hasAnotherPeriod` before existing.
- `CoreHasNoHumanStrings`, `CoreStaysPortable` and the localisation suites
  run as they are; the change adds no literals, no imports and no keys.

## What does not change

The full window and `AccountRow`. The widgets and the phone, which read a
snapshot and have no click. The menu bar label, whose window choice is
`Monitoring`'s separate question. `Preferences`, its store, and the settings
panes.

## Out of scope

Remembering the peek in any form, including per session. A whole-window
toggle. A third period. Any change to what is polled or stored.
