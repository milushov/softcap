# Settings screen — design

Date: 2026-08-30
Status: approved, implemented
Mock-up: `docs/design/settings-screen.html`

## Problem

The prototype has no settings at all. Everything that could be a choice is
hard-coded: notification thresholds of 80 and 95, poll intervals of 60 seconds
and 5 minutes, the row layout, the sort order. An account that once entered the
list can be neither hidden nor forgotten. There is no launch at login, so after a
restart the monitor has to be started by hand.

A settings window with a sidebar of sections is needed.

## Sections

Six, in sidebar order:

1. **Accounts** — the list, each one's state, hide or forget.
2. **Appearance** — theme, menu bar item, row layout.
3. **Notifications** — thresholds, events, quiet hours.
4. **Updates and launch** — poll intervals, launch at login, hot keys.
5. **Services** — enabling providers, the Codex directory path.
6. **About and data** — version, storage locations, "forget everything".

Hot keys were originally meant to be a section of their own, but a screen with a
single field looks empty, so they live in "Updates and launch" alongside the rest
of the app's behaviour.

## Layout

A sidebar, not top tabs: seven or eight tabs get truncated with ellipses, and a
macOS settings window does not stretch. With a sidebar the labels stay whole, and
adding Cursor or Copilot does not break the arrangement.

Icons are monochrome stroked SF Symbols in the label's colour, with no coloured
backplates. The reason is not only taste: **colour already carries meaning in the
limits window** — green, yellow, orange and red encode load. Service brand
colours next to them blur that language and both signals weaken. Service logos in
the account list are monochrome for the same reason: a thin border and a glyph.

**App appearance** — three values: `System` (default, follows macOS), `Light`,
`Dark`. Applied through `NSApp.appearance`: `nil` for system, `.aqua` and
`.darkAqua` otherwise.

## Storage

`UserDefaults`, in `~/Library/Preferences/dev.example.StatusChecker.plist`.
Credentials are not stored there and never will be — they stay in the keychain.

The settings model lives in a new `Packages/Core/Sources/Preferences` module so
that defaults, allowed ranges and threshold ordering can be tested without
launching the app. The UI stays in `App/`.

```swift
struct Preferences: Sendable, Codable, Equatable {
    // Appearance
    var appearance: Appearance          // .system | .light | .dark
    var menuBarContent: MenuBarContent  // .iconOnly | .timer | .percent | .both
    var primaryWindow: PrimaryWindow    // .worst | .session | .weekly
    var rowLayout: RowLayout            // .twoWindows | .compact | .rings
    var ordering: Ordering              // .leastLoadedFirst | .byName
    var showSnapshotAge: Bool

    // Notifications
    var notificationsEnabled: Bool
    var thresholds: [Int]               // [80, 95] by default
    var notifyOnRecovery: Bool
    var notifyWindows: WindowScope      // .session | .weekly | .both
    var quietHours: QuietHours?         // nil — disabled

    // Updates and launch
    var foregroundInterval: TimeInterval // 60
    var backgroundInterval: TimeInterval // 300
    var refreshAfterWake: Bool

    // Services and accounts
    var disabledProviders: Set<ProviderID>
    var hiddenAccounts: Set<String>      // ids hidden from the window
    var codexRoot: String?               // nil — the standard ~/.codex
}
```

These are all plain values, so `Preferences` is `Codable` as a whole and stored
under one key. Separate keys per field would mean more code and drift whenever a
field is added.

## What settings change in existing code

A settings screen is useless while values stay hard-coded. So the work is not
only a new window but making the existing places read `Preferences`:

| Hard-coded today | Reads instead |
|---|---|
| `ThresholdTracker.thresholds = [95, 80]` | `preferences.thresholds`, sorted descending |
| `ThresholdTracker.recoveryLevel` | `preferences.notifyOnRecovery` enables the branch |
| `AppModel.restartTimer` — 60 and 300 | `foregroundInterval`, `backgroundInterval` |
| `MenuBarLabel` — always the timer | `menuBarContent` |
| `menuBarSummary` — always the worst window | `primaryWindow` |
| `orderedForDisplay` — always by load | `ordering` |
| `AccountRowView` — always layout A | `rowLayout` |
| `AppModel.rebuildPoller` — every provider | minus `disabledProviders` |
| The window shows every account | minus `hiddenAccounts` |

`ThresholdTracker` and `orderedForDisplay` currently take their values from type
constants. They will take them as parameters instead — which also makes them
testable against different settings, something impossible today.

## The Accounts section

Each row: logo, name, service and plan, state, a switch.

Three states, computed rather than stored:

- **active in CLI** — the refresh token matches the one currently in the
  `Claude Code-credentials` keychain item. Read directly, never refreshed.
- **refreshed** — the account has a saved refresh token copy and is not active.
- **sign-in needed** — no copy, or the last refresh failed.

The switch hides an account from the limits window without deleting it:
`hiddenAccounts`. A hidden account is not polled, which also saves requests.

"Forget" removes the entry from `StatusChecker-accounts` along with the token
copy. It **does not touch** the CLI sign-in, and the interface says so plainly —
otherwise nobody would dare press it.

### Browser sign-in

An "Add account…" button performs the sign-in from within settings, sparing the
user a trip to the terminal for `claude /login`. Until now subscriptions could
only be gathered by accumulation: an account appeared once the user signed into
it through the CLI, and not before.

The parameters are taken from the constants of the installed Claude Code, not
guessed:

| | |
|---|---|
| authorize | `https://platform.claude.com/oauth/authorize` |
| token | `https://platform.claude.com/v1/oauth/token` |
| client_id | `9d1c250a-e61b-44d9-88ed-5944d1962f5e` |
| manual redirect | `https://platform.claude.com/oauth/code/callback` |
| scope | `org:create_api_key user:profile user:inference` |

Verified on 2026-08-30: an authorization request with these values answers `200`
and serves the sign-in page — no `invalid_client` or `invalid_scope`. The former
address `claude.ai/oauth/authorize` answered `403`: **the domains changed**, which
also means `AnthropicTokenRefresher`, currently pointed at
`api.anthropic.com/v1/oauth/token`, must move to the canonical
`platform.claude.com` — the old address still answers, but it should not be
relied on.

The flow:

1. The app opens a temporary listener on a free `localhost` port.
2. It generates PKCE: a `code_verifier` of 32 random bytes, a `code_challenge`
   that is its SHA-256 in base64url, method `S256`.
3. It opens the system browser at the authorization address with a `redirect_uri`
   pointing at that port, and a random `state`.
4. The person signs in through the browser. The app never sees or asks for a
   password.
5. The browser returns to `localhost`; the app checks `state` and exchanges the
   code for tokens: `POST /v1/oauth/token` with `grant_type=authorization_code`,
   `code_verifier`, `client_id`, `redirect_uri`.
6. The profile is fetched with the new token and the account is saved to
   `StatusChecker-accounts` together with its refresh token.

The localhost redirect was accepted by the server when probed (`200` for both
`localhost` and `127.0.0.1`), but only a real sign-in will settle it. A **fallback**
therefore exists: the same request with `code=true` and the manual `redirect_uri`
displays the code on the page, and settings offer a field to paste it into. The
exchange after that is identical.

An account added this way is in the **refreshed** state: it has its own token
pair, unconnected to the CLI session, so the app refreshes it itself. The
"active account is read-only" rule does not apply — that rule is about the
account whose refresh token matches the one in the CLI keychain item.

The listener lives only for the duration of the sign-in and closes as soon as the
code arrives, or after two minutes. Neither the `code_verifier` nor the tokens are
written to logs.

## The Updates and launch section

**Launch at login** — `SMAppService.mainApp.register()` (macOS 13+). The switch
reads its state from `SMAppService.mainApp.status` rather than storing it: the
user can turn the item off in System Settings, and a stored value would then lie.

**Hot keys** — two: "open the window" and "refresh now". Registered through
Carbon's `RegisterEventHotKey`, the only way to get a global shortcut without
Accessibility permissions. The shortcut recorder is a small `NSView` intercepting
`keyDown`.

This is the most expensive part of the section and the only one needing a C API,
so in the plan it comes last: if the work has to stop early, everything else
already works.

## Opening the settings window

The app is `LSUIElement` — no Dock icon, no application menu bar of its own.
Settings are declared as a `Settings` scene and opened from the limits window.
A "Settings…" item is added to the window's footer next to "Refresh" and "Quit",
with the customary ⌘, shortcut.

## Errors

Settings must not be able to break the app:

- An empty threshold list is valid — it means no load notifications; the
  recovery event still works.
- Poll intervals are bounded to 30 seconds and one hour. A value outside is
  pulled to the nearest bound.
- Disabling every provider is valid: the window shows "No accounts found".
- A non-existent Codex directory makes that provider return `.noData`; the row
  states the reason and other services carry on.
- A corrupt or incompatible plist yields the defaults rather than a crash.

## Tests

- defaults: a fresh `Preferences` gives thresholds `[80, 95]`, intervals 60 and
  300, appearance `.system`;
- interval bounds: 5 seconds is pulled to 30, two hours to one hour;
- thresholds are sorted descending and deduplicated on write;
- `ThresholdTracker` on non-standard thresholds: `[50]` fires at 50, `[]` gives
  no load events but still gives recovery;
- quiet hours: an event inside the quiet window is suppressed, one outside gets
  through, including a window crossing midnight (23:00–09:00);
- hidden accounts and disabled providers are excluded from polling;
- `Preferences` survives an encode/decode round trip without loss;
- corrupt data yields the default set.

All tests avoid the file system: storage is behind a protocol, like
`KeychainAccess`.

## Boundaries

Out of scope: syncing settings between machines, settings profiles, export and
import, a custom colour-scale editor, translation into other languages, and
sign-in to services other than Claude (Codex has its own scheme, and its data is
local anyway).
