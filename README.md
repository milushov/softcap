# Softcap

Claude Code and OpenAI Codex subscription limits in the macOS menu bar.
macOS 14+ · SwiftUI · WidgetKit.

## Build and run

<!-- download:start -->
### [⬇︎ Download Softcap 0.1.7](https://github.com/milushov/softcap/releases/latest/download/Softcap.dmg)

A disk image for macOS 14 and later. Released 13 September 2026 — [all versions](https://github.com/milushov/softcap/releases/tag/v0.1.7).
<!-- download:end -->

Requires **Xcode 26+ / Swift 6.2+** and **XcodeGen** (`brew install xcodegen`).
For signed macOS builds, configure your development certificate and team in
`Signing.local.xcconfig` (git-ignored); see [Signing.xcconfig](Signing.xcconfig).

```sh
make test       # Core tests; no signing required
make test-auth  # Browser sign-in lifecycle tests with fake accounts
make build      # Build the macOS app and widget
make run        # Build and launch the macOS app
make build-ios  # Build for the iOS simulator; no certificate required
make run-ios    # Build and launch in an installed iPhone simulator
```

To compile the macOS app without a signing identity:

```sh
make project
xcodebuild -project Softcap.xcodeproj -scheme Softcap -configuration Debug \
  -derivedDataPath build CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

Unsigned builds cannot use the App Group for widget data and history storage.
The [release workflow](.github/workflows/release.yml) builds macOS on pushes to
`main` except documentation-only changes, then signs and packages a DMG and ZIP.

## Accounts and usage

Open **Settings → Accounts → Add account…**, choose **Claude Code** or
**OpenAI Codex**, and sign in in the browser. Repeat for each subscription.
After saving, Softcap returns to Accounts. **Sign in…** reconnects an account;
**Forget…** removes its saved Softcap credentials without signing the CLI out.

| Source | Readings |
|---|---|
| Claude | Live usage from `api.anthropic.com/api/oauth/usage`; browser grant or the active Claude Code account |
| Codex browser account | Live usage from `chatgpt.com/backend-api/wham/usage`; ChatGPT subscription sign-in |
| Codex local account | Identity from `~/.codex/auth.json`, snapshots from `~/.codex/sessions`; refreshed when session files change |

Usage checks send no prompts. Browser accounts have independent grants.
Adding a Codex account through the browser replaces its local row with live
usage. Local snapshots show their age; Softcap never writes Codex's `auth.json`
or refreshes its CLI token.

For Claude CLI access, use **Allow access…** when Accounts reports a blocked
Keychain read. Startup, timers and **Refresh** never request that dialog.
The active CLI grant is read-only; imported accounts may need another sign-in
after CLI token rotation. Browser grants avoid that dependency.

## Features and defaults

| Feature | Behavior |
|---|---|
| Limits | Five-hour and weekly usage, reset countdowns, reading age |
| Accounts | Hide accounts; sort by load, name, or **Custom** drag-and-drop order |
| Notifications | Thresholds at **80% / 95%** by default, recovery alerts, quiet hours; messages name the limit window |
| Polling | Every **60 s** with the window open, **300 s** in the background; configurable |
| Appearance | System, light, dark; optional minimal window; ten languages including Arabic RTL; VoiceOver |
| Mac widgets | All four sizes: small, medium, large, extra large; data comes from the app |
| Statistics | Weekly-limit charts over the last week or month; local Codex history imported on launch |
| Updates | Daily GitHub check by default; installation starts from the menu or Settings → Updates |

Settings open with **⌘,**. Nine sections: Accounts, Statistics, Appearance,
Notifications, Polling and launch, Updates, Services, Contribute, About and data.

History keeps a reading when usage moves by a point, at most every five minutes,
plus one every half hour regardless while polling; pruned after 35 days.
Cursor, GitHub Copilot and Gemini CLI are placeholders, not implemented providers.

## Data

- **Credentials:** Keychain service `StatusChecker-accounts` (legacy name).
- **Settings:** `~/Library/Preferences/app.softcap.Softcap.plist`.
- **Widget and history:** `snapshot.json` and `history.json` in the App Group
  container; widgets make no network requests.
- **Error reports:** scrubbed failure details, app version and event metadata go
  to `sentry.softcap.app`. Enabled by default in release builds; disable in
  **Settings → About and data → Send error reports**. Debug builds do not report.

## iOS prototype

The iOS 17+ app and widgets share the Mac's models and views. Home-screen widgets
support small, medium and large sizes; lock-screen widgets support the circle and
rectangle — two of the three accessory shapes.

**Account sync from the Mac and sign-in on the phone are not implemented.**
The current Keychain store is local, so a fresh iOS install has no accounts.
Local Codex session files remain Mac-only. Device builds need signing and
provisioning; the Makefile targets the simulator.

## Development

| Path | Contents |
|---|---|
| `App/`, `Widget/` | macOS app, settings and widget |
| `iOS/`, `iOSWidget/` | iOS prototype and widgets |
| `Packages/Core/` | Providers, credentials, monitoring, preferences, shared UI, updates and diagnostics |
| `Tests/AuthenticationTests/` | macOS browser controller and loopback listener tests |

Core logic has no AppKit dependency. User-facing strings belong in the ten
`StatusUI` translation catalogues.

```sh
tools/install-hooks.sh             # Install the pre-commit hook once per clone
tools/decisions-index [substring]  # Find decisions by heading, date and line
tools/mutate <file> <old> <new> -- <command>
```

The hook runs the Core suite, including ten checks for private data in files and
commit history. Mutation testing requires a clean file and restores it from a
copy. Exit codes: **0** — the check failed; **1** — the check passed with the file
broken; **2** — the mutation could not be made.

## Site

`site/` contains the landing page for [softcap.app](https://softcap.app/).

```sh
site/check-widths.sh    # Check layout at 320–1920 px (requires Chrome)
site/deploy.sh --status # Compare local files with HTTPS responses; no SSH
site/deploy.sh          # Deploy through SSH and verify
site/deploy.sh --rollback
```

Deploy runs a width check and verifies SHA-256, Cache-Control, the proxy's saved
state and the container's restart policy. It keeps the previous files and server
configuration for rollback.

## References

- [Authentication](docs/authentication.md) — sign-in, credential ownership and usage sources.
- [Decision log](docs/DECISIONS.md) — append-only rationale; search with `tools/decisions-index`.
- Historical [specs](docs/superpowers/specs/), [plans](docs/superpowers/plans/)
  (start with the note in that directory), and [mockups](docs/design/).
- [Translation helper](tools/add_strings.py) — update all ten catalogues.
