# AI subscription limits monitor — macOS prototype design

Date: 2026-08-30
Status: approved, implemented

## Problem

The user holds three Claude Code subscriptions and one OpenAI Codex. Tracking
what is left in each by hand is awkward: to find out whether an account is
exhausted you have to sign into it. One screen showing all subscriptions at once
is needed.

The prototype is a macOS menu bar app. Clicking the icon opens a small window
listing the accounts: service logo, time until the limit resets, and percentage
used.

An iOS app with a widget is a later stage and not part of this prototype. The
architecture must leave the road open for it.

## Data sources (verified against live accounts on 2026-08-30)

### Claude Code

`GET https://api.anthropic.com/api/oauth/usage` with
`Authorization: Bearer <oauth-token>` and `anthropic-beta: oauth-2025-04-20`.
Answers `200`:

```json
{ "five_hour": { "utilization": 5.0,  "resets_at": "2026-08-30T14:00:00Z" },
  "seven_day": { "utilization": 23.0, "resets_at": "2026-09-05T10:00:00Z" },
  "limits": [ { "kind": "session",    "percent": 5,  "severity": "normal", … },
              { "kind": "weekly_all", "percent": 23, "severity": "normal", … } ] }
```

The `limits` array is what we read: it is self-describing and will survive the
service adding new window kinds. The `five_hour` / `seven_day` fields are the
fallback when `limits` is empty.

`GET https://api.anthropic.com/api/oauth/profile` returns the account identity:
`account.uuid`, `account.email`, `account.display_name`, plus
`organization.rate_limit_tier` (for example `default_claude_max_20x`). Accounts
are told apart by `uuid`; the plan label is built from `rate_limit_tier`.

The access token lives about 8 hours, the refresh token 28 days.

### OpenAI Codex

A direct request to `chatgpt.com/backend-api/codex/usage` answers `403` — the
route is closed. The working source is the local session files in
`~/.codex/sessions/**/*.jsonl`, where the CLI writes a `rate_limits` event:

```json
{ "limit_id": "codex", "plan_type": "plus",
  "primary":   { "used_percent": 0.0, "window_minutes": 300,   "resets_at": 1787867253 },
  "secondary": { "used_percent": 0.0, "window_minutes": 10080, "resets_at": 1788454053 } }
```

`window_minutes` 300 is the five-hour window, 10080 the weekly one. `resets_at`
is Unix time. The identity comes from `~/.codex/auth.json`: the `id_token` field
holds a JWT whose body carries `chatgpt_plan_type` and `chatgpt_account_id`.

**Codex data is a snapshot, not a current reading.** It only updates when the CLI
itself goes online. At the time of checking, the newest snapshot was two days
old. The snapshot's age must be visible in the interface.

## Shape of the data

Both services describe a limit the same way: several windows, each with a
percentage used and a reset time. That is the basis for a shared model which
knows nothing about any particular service.

```swift
struct LimitWindow {
    let id: String           // "session", "weekly"
    let percent: Double      // 0…100
    let resetsAt: Date?      // nil when the service does not say
}

enum Freshness {
    case live(Date)          // fetched by request
    case snapshot(Date)      // read from a local file, age matters
}

struct AccountSnapshot {
    let id: String           // provider plus account identifier
    let provider: ProviderID // .claude, .codex, .cursor, .copilot, .gemini
    let displayName: String  // email or name
    let planLabel: String    // "Max 20x", "Plus"
    let windows: [LimitWindow]
    let freshness: Freshness
    let failure: ProviderFailure?
}

protocol UsageProvider {
    var id: ProviderID { get }
    func discoverAccounts() async throws -> [AccountRef]
    func fetch(_ ref: AccountRef) async throws -> AccountSnapshot
}
```

A new service is added as one type conforming to `UsageProvider`; the interface
does not change. The prototype implements `ClaudeProvider` and `CodexProvider`;
Cursor, GitHub Copilot and Gemini CLI are accounted for by the protocol but not
written.

## Credentials for three accounts

The keychain holds a token only for the account the user is currently signed
into in the CLI. Since they switch with `/login`, earlier tokens are overwritten
— reading all three from disk is impossible. Accounts are gathered two ways,
which gives two modes of operation:

**"CLI mirror" mode.** An account found in the `Claude Code-credentials` keychain
item is used **read-only**. Before every poll the app re-reads `accessToken` from
there; the CLI keeps it fresh itself.

The reason for that restriction: refreshing may rotate the refresh token on the
server side. If the app refreshes, the CLI is left with a stale token and gets
signed out. Read-only rules that conflict out by construction.

**"Refresh from our own copy" mode.** While an account is active, the app copies
its refresh token. When the user moves to another subscription, the account stays
visible: the app refreshes it from that copy. The CLI no longer uses that token,
so rotation disturbs nobody — the same active/inactive distinction rules out the
conflict.

Hence the requirement: the copy must be renewed on every poll while the account
is active. Otherwise, after switching, its token in the keychain is overwritten
and the account is lost for good.

The list therefore fills itself: the user signs into each subscription once with
their usual `/login`, and from then on all three are visible at the same time.

Secrets never leave the keychain and are never written to logs or preference
files.

## Interface

The mock-up with three worked-out row layouts is in
`docs/design/menu-window-variants.html`. **Layout A** was approved.

**Menu bar.** An icon plus a timer, for example `◐ 0:47`. It shows the time until
the reset of whichever window is closest to exhaustion — that is, the window with
the highest percentage across all accounts. The meaning is "how long until the
fullest account frees up". Taking the soonest reset would be wrong: for a free
account it says nothing. The icon colour follows the same window.

**Window.** 322 pt wide, rounded, with the system blur. A list of accounts, each
showing:

- the service logo and an `email · plan` caption;
- a `5h` row — bar, percentage, time to reset;
- a `week` row — the same for the weekly window;
- an age badge when the data is a snapshot: "data from 28 Aug".

Order: ascending by the highest percentage among an account's windows. The least
loaded ends up on top — the one you can go and work in. Accounts with an error
sink to the bottom.

Colour scale: below 50 % green, 50–75 % yellow, 75–90 % orange, above 90 % red.
At the foot of the window, "Refresh" with ⌘R.

## Modules

| Module | Responsibility |
|---|---|
| `ProviderKit` | models and protocol, no network |
| `ClaudeProvider` | `/oauth/profile`, `/oauth/usage`, OAuth PKCE sign-in |
| `CodexProvider` | parsing `rate_limits` from session files, identity from `auth.json` |
| `CredentialStore` | own keychain item, read-only bridge to the CLI |
| `UsagePoller` | polling and the last-snapshot cache |
| `ThresholdNotifier` | threshold notifications |
| `MenuBarApp` | the menu bar item, the window |

Each module is tested on its own: `ProviderKit` depends on nothing, and the
providers receive their HTTP client and file paths through initializer
parameters.

## Data flow

1. On launch `CredentialStore` returns the saved accounts and the window is drawn
   from the last cache — no empty screen.
2. `UsagePoller` walks the providers: once a minute while the window is open,
   once every five minutes in the background.
3. `ClaudeProvider` re-reads the token from the CLI keychain for a mirrored
   account; for others it refreshes its own copy when needed.
4. `CodexProvider` finds the newest session file and takes the last `rate_limits`
   event from it.
5. Snapshots go into observable state and the window redraws.
6. `ThresholdNotifier` compares against the previous snapshot and sends a
   notification when a threshold is crossed.

## Notifications

Three occasions: reaching 80 %, reaching 95 %, and an exhausted account coming
back. The notification fires **on the crossing**, not on every poll above the
level — otherwise a five-minute background poll would turn into a stream of
alerts. The previous value per window per account is kept for that.

## Errors

An error is confined to its own account row and never empties the window:

- network unavailable — the last snapshot and its age are shown;
- `401` with refresh failing — a "Sign in again" button in the row;
- no Codex session files — "run Codex at least once";
- unrecognized response — the row is marked failed, the rest live on.

## Tests

- parsing a Codex session file from fixtures, including a file with no
  `rate_limits` events and one with several — the last is taken;
- mapping the `/oauth/usage` response into the model, including an empty `limits`
  array falling back to `five_hour` / `seven_day`;
- formatting the remaining time: `47 m`, `3 h 39 m`, `5 d 23 h`;
- thresholds: one notification per crossing, repeated only after a reset;
- row ordering.

Network and file system are behind mocks; no test reaches the internet.

## Prototype boundaries

Out of scope: the iOS app and widget; Cursor, GitHub Copilot and Gemini CLI
providers; settings beyond the account list; build signing and notarization.

Usage history and charts were on this list and are no longer: a `Statistics`
section was added later at the user's request. See the decision log.

## The road to iOS

The decision was that the iOS app will call the API itself, receiving tokens
through the iCloud keychain. A consequence to keep in mind: **Codex data is
unavailable to the phone** — it lives in local files on the Mac. So on iOS,
Claude comes straight from the API while Codex arrives as a snapshot the Mac
places in shared storage. `ProviderKit` does not depend on AppKit, so it ports
unchanged.
