# The minimal window

One setting turns the limits window into a list and nothing else: one line per
account, a hairline bar under it, three icons at the foot. No title, no
dividers, no service badges, no plan labels, and no colour until a limit is
close.

## Why a switch and not a redesign

The window earns its density when several accounts are close to a ceiling: two
windows per account, each with a label, a bar, a percentage and a countdown, is
the reading somebody opens the app *to do*. Most openings are not that. They
are a glance to confirm nothing is on fire, and for those the window says nine
things where one would do.

Both readings are legitimate, so this is a setting rather than a new design.
The default stays what it is; nobody's window changes until they ask.

## The setting

`Preferences` gains one field:

    public var minimalWindow: Bool     // default false

Decoded like every other field, through the entry in `init(from:)`:
`read(.minimalWindow, fallback.minimalWindow)`. The synthesised `Codable`
refuses a blob missing any non-optional key, and `PreferencesStore.load()`
answers a refusal with `.defaults` — so adding this field the ordinary way
would silently discard every existing setting on upgrade. That has an entry in
the decision log already; this is it being obeyed.

It is a `Bool` and not a two-valued enum on purpose. A toggle in the settings
pane and a checked item in the menu mean exactly the same thing, and both can
be labelled from the single catalogue key `Minimal window` — an enum would cost
four keys in ten languages to say the same thing.

**In `AppearancePane`** it sits immediately above `Row layout`, and turns that
picker off while it is on: a row layout describes the full window, and the
minimal one does not have one. Disabled rather than hidden — a setting that
vanishes reads as a bug, and a greyed one explains itself.

**`Primary window` acquires a second job.** Today it decides only what the menu
bar label counts. In the minimal window it also decides which of an account's
limits the single line shows. Its default, `Busiest`, is what makes the label
beside the number necessary: the figure switches between the five-hour window
and the weekly one as usage moves, and a number that silently changes meaning
is worse than no number.

## The row

    ┌────────────────────────────────┐
    │  name@example.com  week 71% 4d │
    │  ██████████░░░░░░░░░░░░░░░░░░  │
    │  work@example.com    5h 88% 1h │
    │  ████████████████████████░░░░  │
    │  ↻              ⚙            ⏻ │
    └────────────────────────────────┘

A new view, `MinimalAccountRow`, beside `AccountRow` in `StatusUI` — not a
fourth case of `RowLayout`. That enum describes a row; this setting also strips
the window around it, and one setting governing two scopes is the kind of thing
nobody can predict from its name.

The name is truncated in the middle, the window label and the remaining time
are tertiary, the percentage is monospaced. The bar is 2 pt across the full
width and **grey** while `Severity` is `.ok`; from `.warning` upward the bar and
the percentage both take `severity.tint`. This is the one place the minimal
window spends colour, and it spends it only when there is something to say.

The service badge and the `Claude · Max 20x` line are gone from the row and
reachable as the row's tooltip. That is the idiom this project already uses for
`ProviderFailure.diagnostic`: invisible until somebody looks, which is the right
amount of visible for something needed twice a year.

**Width stays 322 pt.** The height is where the saving is — two accounts go from
about 230 pt to about 110 pt. Narrowing as well would put `week 100 %` and
`Data from 28 Aug` into a box they do not fit in once the interface is in
French or Arabic, and the reading that matters most is the one that would be
cut.

## What survives, and only when it must

- **An overdue reading** — a single line above the list, `%@ old` in
  `Severity.hot.tint`, present only while the figures are older than the polling
  interval says they should be. The ordinary clock in the header (`2:41`) goes
  away with the header: it is decoration next to a reading that is current.
- **A stale snapshot** — the date in tertiary text rather than the orange plate
  the full row draws. Staleness is worth saying and is not urgency, and a second
  colour language in a window built to be quiet weakens the first one.
- **A failure** — the account name and the translated sentence, no bar. The
  diagnostic stays in the tooltip.
- **An empty list** — the same words as today, without the header above them.

## The footer

Three tertiary 11 pt symbols — `arrow.clockwise`, `gearshape`, `power` — spread
across the width, each with a tooltip taken from the existing keys `Refresh`,
`Settings…` and `Quit`, and each keeping the shortcut it has now: ⌘R, ⌘, and ⌘Q.

The alternative was no footer at all, since the right-click menu already carries
those actions. It was rejected because it makes the window depend on a gesture
nothing advertises: a person who does not think to right-click a menu bar icon
would have a window with no way out of it.

## The menu

    Softcap 0.1.47
    ──────────────────
    Refresh
    ──────────────────
    Settings…
    Add account…
    Statistics…
    ──────────────────
    ✓ Minimal window
    ──────────────────
    Check for updates
    ──────────────────
    Quit

`Statistics…` sets `appModel.settingsSection = .statistics` and opens the
settings window. Both it and `Add account…` are already in the catalogues; only
`Minimal window` is new, and it goes into all ten through
`tools/add_strings.py`.

### What `Add account…` costs

`LoginController` is a `@StateObject` owned by `AccountsPane`, so nothing
outside that pane can start a sign-in. Ownership moves to `AppModel` and the
pane observes it instead.

The menu item is the reason, but not the whole gain: as it stands, leaving the
Accounts section during a browser sign-in destroys the controller and the
sign-in with it. Hoisting it fixes that as a side effect.

## Choosing which window the line shows

A pure function, tested on its own rather than through a view:

    extension AccountSnapshot {
        func headlineWindow(for choice: PrimaryWindow) -> LimitWindow?
    }

It lives in `StatusUI`, beside the view that asks it — the module already
imports both `ProviderKit` and `Preferences`, and the answer is wanted where it
is drawn. `Monitoring` makes the same choice across accounts for the menu bar
label, which is a different question and stays where it is. `Busiest` returns
`peakWindow`; `Five-hour` and `Weekly`
return that window, falling back to whichever window exists when the requested
one does not — a Codex account has what its session files gave it, and a line
that disappears because the chosen window is missing would read as a broken
account. An account with no windows returns `nil` and the row draws its name
alone.

## What does not change

The widgets and the iOS app keep drawing `AccountRow`. This setting is about
the Mac window, `SharedSnapshot` does not carry it, and a widget has no footer
or header to strip. `RowLayout` keeps its meaning for the full window.

## Tests

- `PreferencesTests`: the default is `false`; a stored blob without the key
  still decodes every other field.
- `StatusUITests`: `headlineWindow(for:)` — `Busiest` picks the peak, a missing
  requested window falls back to the one present, no windows gives `nil`.
- The localisation suite already checks that key sets and placeholders match
  across the ten catalogues; the new key passes through it.
- `CoreHasNoHumanStrings` is unaffected: `StatusUI` is exempt by design, and
  the new `Bool` in `Preferences` carries no text.

## Known risk

Toggling the setting while the window is open. `NSPopover` is not obliged to
recompute its height when its hosted content changes, and this change alters
the height by more than half. If it does not resize on its own, the controller
sets `contentSize` explicitly. This has not been verified yet — it is the first
thing to check once the view exists.

## Out of scope

Applying the minimal treatment to the widgets or the phone. Making the window
width configurable. Any change to what is polled, stored or notified — this
setting decides what is drawn and nothing else.
