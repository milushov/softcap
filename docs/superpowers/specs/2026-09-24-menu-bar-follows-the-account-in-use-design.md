# The menu bar follows the account in use

The figure beside the menu bar icon stops meaning "the fullest limit anyone
has" and starts meaning "the limit of the account you are working with right
now". Which account that is, is inferred from the readings already being taken:
the one whose usage rose most recently is the one being used.

A new `Account shown` setting keeps the old meaning one click away. It defaults
to the new behaviour.

## Why it is inferred rather than read

The app could ask the CLI. It used to: the entry of 2026-08-30, *The active
Claude account is read-only*, is built on matching the refresh token in the
`Claude Code-credentials` keychain item, and that match names the account the
CLI would use. That route is closed. *Softcap opens one keychain item, and it
is its own* (2026-09-14) ended every read of anybody else's item, because an
unanswered keychain prompt had been disabling the whole app.

Nothing else on the machine would answer either — the CLI keeps no readable
"current account" anywhere the app is willing to look, and the whole point of
this feature is that it must not go looking. So the answer has to come out of
the polls, which are happening anyway.

That constraint turns out to be a feature. Reading the CLI would answer for
Claude alone; a rule built on readings answers for every provider the app
supports, including ones it has not met yet.

## What counts as being in use

A poll arrives. For every account that answered — one carrying a `failure` is
skipped, because a failed read is an unknown, not a measurement, which is the
rule `UsageHistory.record` already follows — every window is compared with the
percentage last seen for it:

- **Higher.** A rise. The account is noted as having risen, now, by that many
  percentage points. An account's rise for the poll is the largest among its
  windows: Claude's session and weekly move together, Copilot has only the
  monthly one, and taking the largest asks no questions about which window
  matters.
- **Lower.** The window reset. This is not activity, and it is not evidence of
  anything — the mark is moved and nothing is recorded.
- **Unchanged.** Nothing.
- **Never seen before.** The mark is set and nothing is recorded. Without this
  the first poll after a fresh install is a rise from nothing for every account
  at once, and the answer would be whichever of them happened to be biggest.

**The account in use is the one whose most recent rise is the most recent of
all.** Where two rose in the same poll — running Claude Code and Codex side by
side does this — the larger rise wins.

The comparison uses a floor of 0.01 percentage points. That is protection
against `Double` jitter and nothing more: it is not a threshold for "worked
enough", and any real rise, however small, counts.

## Why the last rise rather than the fastest burn

"Whichever is melting fastest" was the obvious reading of the idea, and it is
the wrong measure for two reasons.

Percentages from different services are not comparable. Claude's five-hour
window, Codex's, and Copilot's monthly allowance are different sizes covering
different things, so a percentage point per hour of one is not a percentage
point per hour of another. A rate ranking across providers compares nothing.

And a rate needs a window to be measured over, which puts lag between switching
accounts and the menu bar noticing. "Who rose last" has no window: it changes
on the poll after you switch.

Rate is not thrown away: it settles ties inside a single poll. That comparison
is no more principled than the one rejected above — a Claude point and a Codex
point are still different things — but a tie has to be broken somehow, it is
broken the same way every time, and either answer is defensible, because both
accounts genuinely were used in the last minute.

## Standing still

Stopping for an hour does not change which account you will come back to, so
the answer does not decay. This needs no mechanism: the most recent rise does
not stop being the most recent because time passed. The account in use changes
when another account rises, and at no other moment.

One consequence worth naming. The account you last used may have its window
reset while you are away, and the menu bar will then show it at 0%. That is
honest — it is the account you are on, with a fresh session — and it is what
falls out of the rule with nothing bolted on.

## The tracker

`ActiveAccountTracker`, a value type in `Monitoring`, beside `menuBarSummary`
and `UsageHistory`, which is where every other "what do these readings mean"
question in this project is answered.

```swift
public struct ActiveAccountTracker: Sendable, Equatable {
    /// Below this, a difference is `Double` noise rather than usage.
    public static let floor = 0.01

    public init()
    /// Picks up where the last run left off.
    public init(seededFrom history: UsageHistory)

    public mutating func observe(_ snapshots: [AccountSnapshot], at now: Date)

    /// The account whose usage rose most recently, or nil if none ever has.
    public var accountInUse: String? { get }
}
```

It holds the last percentage seen per account and window, and per account the
time and size of its last rise. Nothing else, and nothing on disk.

**Seeding.** A fresh tracker knows nothing, and a menu bar that falls back to
the busiest account for the first few minutes of every launch would be a
feature that works except when you have just opened your laptop. So the tracker
is built from `UsageHistory`, which is loaded at startup already: it walks the
kept readings, takes each account's last rise, and takes the last percentage
per window as its starting mark.

The kept readings are thinned — no two closer than five minutes, and an
unchanged one only every half hour — so a seeded timestamp is approximate. It
only has to order accounts against each other, and for that it is enough. The
marks being up to half an hour stale is also harmless: the first live poll may
then see a rise that happened slightly earlier, and attribute it to the account
that really made it.

## The setting

```swift
public enum MenuBarAccount: String, Codable, Sendable, CaseIterable {
    case inUse, busiest
}
```

Default `.inUse`. A `Picker` in `AppearancePane`, below `In the menu bar` and
above `Primary window` — the three of them are one question asked three ways,
and they should be read together.

Three new keys across the ten catalogues via `tools/add_strings.py`: the
picker's title and its two cases.

`Primary window` keeps its three choices and starts meaning them **within** the
chosen account: `Busiest` is now the fuller of that account's windows rather
than the fullest window anybody has. Under `Account shown: Busiest` nothing
about it changes.

## `menuBarSummary`

```swift
public func menuBarSummary(
    _ snapshots: [AccountSnapshot], now: Date,
    window: PrimaryWindow = .worst,
    account: MenuBarAccount = .busiest,
    inUse: String? = nil
) -> MenuBarSummary?
```

The defaults describe today's behaviour so that existing callers and tests keep
saying what they already say. The app passes both explicitly.

`MenuBarSummary` gains `accountID: String?` — nil when the figure came from the
whole list. The figure and the account it belongs to then travel together and
cannot fall out of step, which matters because the spoken label is built from
both.

Under `.inUse` the figure is taken from the named account by the `PrimaryWindow`
rule. It falls back to today's behaviour in three cases, all of them the same
case really — there is no account to speak for:

- the setting is `.busiest`;
- no account has ever been seen to rise, on a first launch with an empty
  history;
- the named account is not in this poll's list, or is in it with no windows —
  hidden, signed out, or failed this time round. A menu bar showing nothing is
  worse than a menu bar showing the neighbour for one poll.

## The popover marks the row

The figure in the menu bar will not match anything obvious in the list — 43%
when the top row says 91% reads as a bug. A small dot on the row of the account
in use answers it without a sentence.

The dot follows the same setting: under `Account shown: Busiest` there is no
dot, because that setting is how somebody says they do not want this idea. One
switch, one behaviour.

It is drawn in both the full and the minimal row. VoiceOver needs one new
string for it — the dot is the only part of this change that says something
the existing catalogues cannot.

## What the menu bar says out loud

`spokenMenuBar` currently reads "Busiest: 43% used, 2h left". When the figure
follows the account in use, the first word is false, in the one place a person
cannot check it against the screen.

It gains the account, and the word is replaced by that account's identity —
"Claude, someone@example.com, Max 20x: 43% used, 2h left". This needs no new
string: the template `"%1$@: %2$@ used, %3$@ left"` already takes the name as
its first argument, and `identity(of:)` already assembles exactly that phrase
for the account rows. `Busiest` stays as the name under the other setting.

## Two things left alone

**The widget.** It shows the busiest account, and it goes on doing so. It is a
separate process reading a snapshot, it has no tracker, and a glance at a
desktop is not the same question as a glance at the menu bar you are working
under.

**Notifications.** `ThresholdTracker` watches every account and is untouched.
This matters, because it is what the change costs: the menu bar stops warning
about the account nearest its limit. Work on a fresh account while another sits
at 95% weekly, and the strip will not say so. The notification still will.

## Settings apply at once

Changing `Primary window` today reaches the menu bar only at the next poll —
up to five minutes of a setting that appears not to work. `preferences.didSet`
recomputes the summary for both it and `Account shown`.

## The site and the README

`index.cell_timer_p` promises "Whichever limit is closest to running out, and
how long until it frees up". With the new default that describes the setting
nobody chose. The key is rewritten in all ten `site/strings/*.json`, the site
is rebuilt, and the README paragraph on the menu bar follows.

## Tests

`MonitoringTests`, against `ActiveAccountTracker`:

- the first poll of all sets the marks and names nobody;
- a rise is noticed, and names that account;
- a fall is a reset: it is not activity and does not move the answer;
- two rises in one poll are settled by size;
- an account whose reading failed is skipped, and does not lose its standing;
- the answer holds across polls where nothing moves;
- a rise below the floor is noise and is ignored;
- a tracker seeded from a history names the account that history's last rise
  belongs to;
- a seeded tracker does not re-count a rise already in the history.

Against `menuBarSummary`: `.inUse` takes the named account; it honours
`PrimaryWindow` within that account; it falls back on each of the three paths;
`accountID` is nil exactly when the figure came from the whole list.

`StatusUITests`: the spoken label names the account under `.inUse` and says
`Busiest` under `.busiest`; the dot appears on the right row in both layouts and
on no row under `.busiest`.

The catalogue key-set check and `CoreHasNoHumanStrings` cover the new strings
without being asked.

## What it costs

A guess, presented as a fact. The rule cannot distinguish "Roma is typing into
this account" from "a scheduled job spent a little of it", and there is no
signal available that could. Ten minutes of the wrong account in the menu bar is
the failure, and `Account shown: Busiest` is the way out of it.

Detection is as slow as polling: a minute with the window open, five in the
background. Switching accounts and looking immediately will show the old one.

`Primary window` quietly changes meaning for anyone with more than one account.
Its labels do not change, and under the old setting neither does its behaviour,
but the same word now describes a smaller scope.
