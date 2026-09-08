# In-app updates

Softcap checks GitHub for a newer release, downloads it, verifies it, replaces
itself and restarts. The check is quiet: it never opens a window on its own.

## Why this shape

The app is published as a GitHub release already — a disk image, a zip of the
bundle, and `SHA256SUMS.txt`. Everything an updater needs is there; nothing new
has to be hosted.

Three routes were considered.

**Sparkle** is the standard, and it was rejected for one reason: it brings its
own window with its own strings, and those follow the *system* language. Softcap
has a language switcher that changes every label without a restart. An update
window that ignores it is a visible seam in the one app that made a point of not
having one. Sparkle would also be the project's first external dependency.

**Check and open the browser** was rejected for the opposite reason: it leaves
the person doing the same drag they do today, and leaves the Gatekeeper dialog
in place.

**Our own updater** costs the most code and buys the most: ten languages, our
own view, no dependency, and — because `URLSession` does not set
`com.apple.quarantine` the way a browser does — an update that opens without the
"cannot be opened" dialog the README currently apologises for.

## Precondition: the app does not know its own version

`project.yml` sets `CFBundleShortVersionString: "0.1"` as a literal on the app
target, while the widget beside it uses `$(MARKETING_VERSION)`. The release
workflow passes `MARKETING_VERSION=0.1.<run>` on the command line, so the widget
follows it and the app does not. A published build reports itself as `0.1`.

Nothing depended on this before. The updater depends on it entirely: an app that
misreports its version is permanently out of date. The literal becomes
`$(MARKETING_VERSION)`, and `CFBundleVersion` — absent from `project.yml`, which
is why the About screen shows a bare `1` — is set from it too.

This is fixed first, and separately, because it is a bug that exists without the
feature.

## Versions

Releases are tagged `v0.1.42`; the bundle carries `0.1.42`.

`ReleaseVersion` parses either spelling and compares component by component,
numerically. String comparison would put `0.1.10` before `0.1.9`, which is the
first case the tests pin. Missing components count as zero, so `0.1` and `0.1.0`
are the same version.

A version that is not newer is never offered. A locally built app reports `0.1`
and will therefore see every release as an update, which is true and is left
alone.

## The check

`GET https://api.github.com/repos/milushov/softcap/releases/latest`

`ReleaseFeed` decodes `tag_name`, `body`, and the `Softcap-<version>.zip` asset
from the response. A release without that asset is not an update — it is a
malformed release, and reported as one rather than half-installed. Drafts and
prereleases are excluded; `/releases/latest` already excludes them, and the
decoder refuses them anyway so the rule does not live only in a URL.

Sixty unauthenticated requests an hour per address is the GitHub limit. One
check a day per person is not near it.

### When

At launch, and once every twenty-four hours after. `lastUpdateCheck` is stored
in `Preferences` so a burst of restarts does not become a burst of requests.
`checksForUpdates` turns the whole thing off.

`UpdateSchedule.isDue(lastChecked:now:)` takes the moment as a **required**
argument. This is the rule established when `events(for:now:)` lost its default:
a test that leaves `now` to the system clock passes all evening and fails at one
in the morning. The guard test for that default is copied here.

### How loudly

Not at all. A found update changes two pieces of text and opens nothing:

- the right-click menu item reads `Update to 0.1.47…` instead of
  `Check for updates…`
- the settings footer reads `Update to 0.1.47 · 0.1.42`

No notification, no window, no badge. The person clicks or does not.

## The install

1. **Download** the zip to a temporary directory, reporting progress.
2. **Verify** — fetch `SHA256SUMS.txt`, find the line naming that zip, compare
   against the SHA-256 of what arrived. A mismatch stops here and nothing is
   written outside the temporary directory.
3. **Unpack** with `ditto -x -k`, then check the result is a bundle carrying the
   expected bundle identifier and the expected version. A zip that unpacks to
   something else is not installed.
4. **Check the signature.** If the running app carries a Team ID, the downloaded
   one must carry the same. An ad-hoc build has no identity to compare and this
   step is skipped — which is stated plainly rather than presented as a check
   that ran.
5. **Replace** with `FileManager.replaceItemAt`, atomic on APFS: the original is
   kept as a backup and removed only once the new bundle is in place. If the
   destination is not writable — the app sitting in `/Applications` under
   another account — this fails with an identifier the interface turns into
   advice, and nothing is half-swapped.
6. **Restart.** A detached process waits for our pid to exit and runs `open`;
   the app terminates. For an agent with no documents and no windows worth
   keeping, restarting is a blink of the menu bar icon, so it always happens
   immediately. There is no "ready, restart later" state to get wrong.

### What the verification is worth

The checksum arrives from the same origin as the file. It catches a truncated or
corrupted download; it does not catch a GitHub that has been taken over, because
whoever could replace the zip could replace the sums beside it. What protects
against that is TLS and the decision to trust GitHub with the release, which the
project already makes every time somebody downloads the disk image by hand.

The signature check in step 4 is the one that would notice a swapped bundle, and
it only works for builds signed with a Developer ID. Saying so is the point: the
alternative is an interface that implies a check nobody performed.

## Where it lives

A new `Updates` product in `Packages/Core`, not listed among the iOS target's
dependencies — the same arrangement `CodexProvider` already has.

| Type | Responsibility | Pure |
|---|---|---|
| `ReleaseVersion` | parse and compare `0.1.42` / `v0.1.42` | yes |
| `Release` | version, notes, asset URL, size | yes |
| `ReleaseFeed` | decode the GitHub releases response | yes |
| `Checksums` | parse `SHA256SUMS.txt`, look a file up by name | yes |
| `UpdateSchedule` | whether a check is due, given an explicit moment | yes |
| `UpdateInstaller` | download, verify, unpack, replace, restart | no |

Failures are identifiers, as `ProviderFailure` is: `.network`,
`.checksumMismatch`, `.malformedRelease`, `.signatureChanged`, `.notWritable`,
`.unpackFailed`. The sentences are assembled by the interface.

The architecture rule holds. Release notes are text, but they arrive over the
network — they are data, like a rate-limit number, not a label written into a
model. `CoreHasNoHumanStrings` scans for literals and for reaching at
`Localization`, and this module does neither.

### Requests go through the one door

`NothingElseLeavesYourMac.oneTypeBuildsEveryRequest` asserts that exactly one
file in the project builds a `URLRequest`. That rule is what makes the host list
beside it worth reading, and it is kept.

Downloading a ten-megabyte file with a progress bar needs more than the existing
`get`. `URLSession.download(from:)` takes a bare URL and would slip past the
guard on a technicality — which is worse than failing it. Instead a second
protocol, `FileDownloader`, is declared and implemented in `HTTPClient.swift`.
Providers keep the small protocol they have; every request in the project is
still built in one file.

## What is on screen

Nothing new opens. There is no sheet and no second window: everything happens on
a settings screen, inside the window that already exists.

### The right-click menu

Gains a version header, matching what the reference app does:

```
Softcap 0.1.42          ← disabled, dimmed
────────────────────
Refresh              ⌘R
────────────────────
Settings…            ⌘,
Check for updates…      ← or "Update to 0.1.47…"
────────────────────
Quit Softcap         ⌘Q
```

Both the settings item and the update item open the same window; the update item
selects the Updates screen first.

### The settings footer

A row beneath the sidebar and the detail area, spanning the window, right
aligned and quiet: `Check for updates · 0.1.42`. The left half is a link that
selects the Updates screen; the version is a plain label. It is visible from
every screen, which is what makes it the primary surface.

### The Updates screen

Holds the whole flow, in the scrolling detail area the other screens use:

- the current version, and when the last check ran
- when one is available: the new version and the release notes, rendered from
  the release body with `AttributedString(markdown:)`
- an `Update` button, which becomes a progress bar with the current phase
- on failure: the sentence for that identifier, and a link to the release page
  as a way out that does not depend on the updater working
- a `Check automatically` switch

Closing the window during a download does not cancel it — the work belongs to a
model, not to a view. The app restarts when it finishes.

### Two renames the feature forces

The sidebar already has a section called **Updates**. It is about poll frequency,
launch at login and hot keys. Leaving it would put app updates under *About*
while *Updates* means something else — a confusion this feature introduces and
should therefore resolve.

- `.updates` → `.polling`, titled **Polling and launch**. Its
  `arrow.clockwise` icon suits polling better than it ever suited updates.
- a new `.updates`, titled **Updates**, icon `arrow.down.circle`.

`SettingsWindow.open()` reaches the window through the system's ⌘, menu item and
owns none of its state, so it cannot select a section. `AppModel` gains
`settingsSection`; `SettingsView` binds its selection to it, and a caller sets it
before opening. No new plumbing type.

## What this changes outside the feature

**`project.yml`** — the version literal, as above.

**`NothingElseLeavesYourMac`** — `api.github.com` and `github.com` join the
named hosts, each with its reason: the first is the release feed, the second
is where an asset is downloaded from. The address the download redirects to
is not named here, because it is not named in the source either and the scan
reads source. The test exists for exactly this moment.

**The promise on the landing page.** It reads:

> Credentials stay in the keychain, never copied into preferences or logs.
> No telemetry; nothing else leaves your Mac.

A version check is a request that leaves the machine. It carries nothing about
the person — no identifier, no usage, no account — but GitHub sees an address,
and the sentence as written says that does not happen. It becomes:

> Credentials stay in the keychain, never copied into preferences or logs.
> No telemetry. The only other request is a daily check for a new version,
> and it can be switched off.

Quietly leaving the old wording would be the worse outcome by a distance: the
guard test would have caught the host and the page would have gone on making a
claim that stopped being true.

**Ten catalogues** — every new string through `tools/add_strings.py`.

## Preferences

Two fields:

```swift
public var checksForUpdates: Bool     // default true
public var lastUpdateCheck: Date?
```

No "skipped version": nothing appears uninvited, so there is nothing to dismiss.

## Tests

Unit, in `Packages/Core`:

- `ReleaseVersionTests` — `0.1.9 < 0.1.10`, the `v` prefix, equality across
  `0.1` and `0.1.0`, malformed input, and that an older release is not an update
- `ReleaseFeedTests` — a captured GitHub response decodes; a release with no zip
  asset is `.malformedRelease`; a prerelease is refused
- `ChecksumsTests` — the `<hash>  ./Softcap-0.1.47.zip` format, lookup by name,
  a missing entry, a mismatch
- `UpdateScheduleTests` — due and not due, with the moment passed explicitly

Guard tests, in the house style:

- `TheUpdaterVerifiesBeforeInstalling` — run the installer against a zip whose
  checksum does not match and assert nothing was written outside the temporary
  directory. Behavioural, not a source scan: the claim is about what the code
  does, not about what it contains.
- `TheUpdaterNeverInstallsOlder` — offered a lower version, it reports up to
  date and installs nothing.
- `AskingWhetherToCheckRequiresAMoment` — `UpdateSchedule` has no default for
  `now`, the same guard `ThresholdTracker` carries and for the same reason.

## Order of work

1. The version literal in `project.yml`, alone.
2. `ReleaseVersion`, `Checksums`, `UpdateSchedule`, `ReleaseFeed` — pure, with
   their tests, no interface.
3. `FileDownloader` in `HTTPClient.swift`; `api.github.com` and `github.com`
   added to the host list; the landing sentence rewritten.
4. `UpdateInstaller` and its behavioural guards.
5. The Updates screen, the two renames, `settingsSection` on `AppModel`.
6. The menu header and item, the settings footer.
7. Strings in ten languages; the decision log.
