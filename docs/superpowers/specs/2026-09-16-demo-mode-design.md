# Demo Mode — Design

**Goal:** a person who has never signed in — an App Review reviewer on a clean
machine, or anybody evaluating the app before paying for a subscription — opens
Softcap and sees it working: three accounts, six meters, a menu bar countdown,
a month of history on the chart, and limits visibly being spent. Everything is
labelled as sample data, and nothing about it touches the keychain, the history
file or the notification centre.

**Spec for:** the second rejection of 0.1.22 under guideline 2.1(a), review date
2026-09-16, submission `1a6a70ee-1471-4fa6-8c2b-3de7d3c4986b`: *"we need a
populated demo account/demo mode that shows real content on all pages"*.

## Why this is the right fix rather than a demo account

Softcap reads subscription usage for Claude and Codex. To see a single number a
person needs a paid plan with one of those providers and an OAuth grant obtained
in a browser. A reviewer has neither, so the honest reading of the rejection is
that the app is unreviewable without one — and it is.

The alternative Apple names first, a demo account, cannot be given. It would mean
putting live Anthropic and OpenAI credentials into App Store Connect: against
those providers' terms, impossible to carry through a browser sign-in with a
second factor, and forbidden outright by this repository's rule about published
values. A demo *mode* is the other half of the same sentence in the guideline,
and it is a real feature rather than a concession — the first thing anybody asks
of a usage monitor is what it looks like with usage in it.

The mode is therefore visible, documented, and available to everybody. A mode
that only App Review can reach is a hidden feature, which is its own rejection
under 2.3.1.

## When demo is on

`Preferences` gains one field:

```swift
/// Whether sample data stands in for accounts. `nil` means nobody has decided.
public var demoMode: Bool?
```

Three states, because two are not enough to survive an upgrade.

- `true` / `false` — somebody chose, in the Accounts pane. Honoured as written.
- `nil` — nobody chose. Resolves to "demo is on" when the first poll has
  finished and found no accounts, and to "off" otherwise.

The first successful sign-in writes `false`, permanently: once a person has an
account of their own, samples would be in the way.

The third state exists for the upgrade from 0.1.22. Stored preferences written
by that build carry no `demoMode` key, so every existing installation decodes
`nil` — and every existing installation has accounts, which resolves `nil` to
off. A plain `Bool` defaulting to `true` would have greeted them with three
invented accounts on the morning they updated.

## The data

The landing page at softcap.app already recreates the app's window in CSS, with
three accounts chosen to walk the whole colour scale. The demo shows those three,
so that the website, the App Store screenshots and the running app are one
picture rather than three.

| account | plan | 5h | week | note |
|---|---|---|---|---|
| `alex@example.com` | Codex · Plus | 0%, no reset | 39%, 3d 22h | stale snapshot, so the "Data from …" badge shows |
| `sam@example.com` | Claude · Max 20x | 16%, 2h 04m | 80%, 3d 11h | |
| `sam.k@example.com` | Claude · Max 20x | 100%, 41m | 55%, 5d 16h | busiest; the one the menu bar and the widget name |

`alex`'s session window stays at zero with a dash where a time would be. It is a
real Codex state — no session started yet — and a row that demonstrates it is
worth more than a third moving bar.

These values live in one new type, `DemoData`, compiled into the shipping app.
`App/ScreenshotFixtures.swift` folds into it, so `make screenshots` photographs
the same three accounts the app shows. The store screenshots are re-taken as part
of this work.

The addresses stay on `example.com`, reserved by RFC 2606, for the reason the
screenshot fixtures already give: the real window names the author's own
mailboxes and says how much of each subscription he has spent, and a store
listing is permanent and public.

## The motion

A demo clock runs at sixty times real time from the moment the app launches.
Every displayed value is a pure function of it — there is no simulation state to
keep, restore or get wrong.

At real elapsed `t`, demo elapsed is `e = 60t`. Each window carries a start
percent, the demo-time distance to its first reset, its natural length (5h or
7d), a peak it climbs to, and a residue it falls back to.

- First cycle, while `e < resetsAfter`:
  `percent = start + (peak − start) · e / resetsAfter`
- Afterwards, cycle by cycle over `length`, from `residue` to `peak`.

So each window fills as its countdown empties and arrives at its peak exactly
when the clock reaches zero, then drops and begins again. The demo loops forever
and never freezes, which matters for a reviewer who leaves the window open.

A window with no reset does not move at all: there is no cycle to be partway
through. That is `alex`'s session window, and it is the only still bar on screen.

At `t = 0` every number is exactly the landing's.

The peaks and residues, chosen so that no two windows crest together — four bars
arriving at once reads as an animation rather than as a measurement:

| window | start | resets after | peak | residue |
|---|---|---|---|---|
| `alex` 5h | 0% | — | — | — |
| `alex` week | 39% | 3d 22h | 62% | 6% |
| `sam` 5h | 16% | 2h 04m | 88% | 2% |
| `sam` week | 80% | 3d 11h | 97% | 8% |
| `sam.k` 5h | 100% | 41m | 100% | 3% |
| `sam.k` week | 55% | 5d 16h | 79% | 5% |

`alex`'s stale badge dates from a fixed eighteen days before launch, so it always
reads as an old reading rather than as a date that drifts into the future.

The statistics chart keeps the generator the screenshot fixtures already use —
four weeks of three-hourly readings per account, each climbing through its week
and dropping at the reset, with the cycles deliberately out of phase — built
against `DemoData`'s three accounts and held in memory.

**Why sixty.** A five-hour window passes in five real minutes, so a session bar
gains about a third of a percent per second and the integer on screen changes
every two to three seconds — movement a person notices without watching for it.
`sam.k`'s "41m" empties in forty-one seconds and visibly resets, so a minute of
attention shows a whole cycle. Weekly windows crawl, as weekly windows should.

**How the countdown gets there.** The views compute the remainder as
`resetsAt − now` against the real clock, and they are not changed. Instead the
demo regenerates its snapshots once a second and stamps each window with
`resetsAt = Date() + demoRemaining`. The label therefore reads 41m at launch and
loses a minute every second, which is the accelerated clock made visible rather
than hidden.

The 1 Hz regeneration lives in `AppModel`, on a timer that exists only while demo
is on, and it recomputes the menu bar summary in the same pass so the countdown
in the menu bar moves whether or not the window is open. Turning demo off
invalidates the timer; a person who never turns demo on pays nothing.

## Where it shows, and how it says what it is

Every surface that can show sample data says so. The wording is one catalogue
key, translated into all ten languages.

- **The window**, below the rows and above the buttons: a thin line reading
  *Demo — sample data*, with *Sign in* beside it, which opens Settings at the
  Accounts pane.
- **The minimal window**, the same line at the bottom. That window has no header
  and no footer, so this is the only thing on it that is not a reading — which is
  the price of showing invented numbers at all.
- **Settings → Accounts**, a banner above the list carrying the switch that turns
  demo on and off. The switch is present whether or not demo is on, so somebody
  who wants to see what the app does can go back to it.
- **Settings → Statistics**, the same line under the chart.
- **The widget** shows the same three accounts, and the app writes them only if a
  widget actually exists — the rule from 2026-09-14 does not change here. It is
  written on the ordinary poll cadence and when demo is switched, never at the
  1 Hz the window moves at: a widget redrawn every second would spend a person's
  battery to animate invented numbers.

## What demo must never touch

Sample readings are not readings. In demo the app must not:

- merge samples into `SharedStore.historyURL`. The statistics chart draws from an
  in-memory history built for the occasion; the real month of readings on that
  machine is neither shown nor overwritten;
- pass demo percentages to `ThresholdTracker`. `sam.k` sits at 100% and would
  otherwise fire a notification within seconds of the first launch;
- read or write the keychain. The Accounts pane answers from `DemoData` instead
  of `CredentialStore`, exactly as the screenshot lane already does;
- leave demo data behind. Turning demo off republishes the widget snapshot in the
  same turn, or the desktop keeps showing `sam.k@example.com` after the person
  has signed in as themselves.

Polling, sign-in and every other real path stay armed while demo is on, so
pressing Add Account works from a demo window and the mode ends the moment the
account arrives.

## Tests

- `TheDemoMatchesTheLanding` — the three addresses, plans and six percentages in
  `DemoData` are the ones in `site/src/index.body.html`. Both directions, like
  `TheLandingUsesTheAppsWords`: a number changed on the page without changing the
  app fails, and the reverse fails too.
- `TheDemoTouchesNothingReal` — with demo on, the history store is never written,
  the tracker is never fed, and no keychain read is attempted.
- `TurningDemoOffClearsTheWidget` — the published snapshot after the switch flips
  carries no demo account.
- `TheDemoSaysItIsADemo` — every surface that can display `DemoData` also carries
  the label key, so a new screen cannot show samples silently.
- `DemoSurvivesAnUpgrade` — preferences encoded without the key resolve to off
  when accounts exist.
- The existing catalogue-parity suite covers the new strings in ten languages.

## Strings

New keys, added with `tools/add_strings.py` so all ten catalogues stay in step:
*Demo — sample data*, *Sign in*, *Show sample data*, and the Accounts banner
sentence. No human-facing string goes into `Packages/Core` outside `StatusUI`.

## What ships alongside

- `docs/DECISIONS.md` — an entry recording that the app answers 2.1(a) with a
  mode rather than an account, and what that costs.
- `docs/APP-REVIEW-DEMO-MODE.md` — the reply for Resolution Center and the text
  for App Review Information → Notes, written the way
  `docs/APP-REVIEW-NETWORK-SERVER.md` already is. The notes must keep the
  network.server paragraph as well: both answers travel with the next submission.
- Re-taken store screenshots, from `make screenshots` against the new data.
