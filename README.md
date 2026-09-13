# Softcap

A macOS menu bar app showing how much is left of your Claude Code and OpenAI
Codex subscription limits, in one window. Widgets on the Mac desktop and on the
iPhone home and lock screens, and a phone app, all drawn from the same code.

## Install

<!-- download:start -->
**No build is published yet.** The release workflow is written and runs on every
push to `main`, but it has not produced one — see `.github/workflows/release.yml`.
Until it does, build it yourself: `make build`, below.
<!-- download:end -->

When there is one: open the image and drag the app to Applications. The workflow
rewrites the block above on every release, so the link points at the newest build
and never goes stale.

Builds made without an Apple Developer ID are signed ad-hoc, and macOS refuses
those on first launch. Right-click the app and choose Open to confirm once, or:

    xattr -dr com.apple.quarantine /Applications/Softcap.app

The release notes say which of the two a given build is.

Once it is running, Softcap updates itself. It asks GitHub for the newest
release once a day and says so in two places and nowhere else: the item under
Settings in the right-click menu, which reads *Update to 0.1.47* instead of
*Check for updates*, and the footer of the settings window. Nothing opens on
its own. The Updates screen has the switch that turns the check off.

The version line at the top of that menu says which build is running. It does
not change when an update is found — it is the answer to a different question.

What it installs is checked four ways — the bytes match the checksums the
release published, the archive opens into a bundle, that bundle is Softcap at
the version claimed, and a Developer ID build must be signed by the same team.
They are the only checks there are: a download the app makes itself is not
quarantined the way a browser's is, so the dialog above does not come back, and
nothing downstream looks at it either. `docs/DECISIONS.md` says what that is
worth and what it is not.

## Build

    make test      # logic tests, no Xcode needed
    make build     # build Softcap.app
    make run       # build and launch
    make build-ios # build the iOS app
    make run-ios   # build and launch it in a simulator

Requires Xcode 26+ and `xcodegen` (`brew install xcodegen`).

`make test` and `make build-ios` need nothing set up. **`make build` does**: the
Mac app and its widget carry an App Group entitlement, and macOS will not sign
one without a development team, so a fresh checkout fails with *"requires a
provisioning profile"* rather than building ad-hoc.

Two ways past it. Create `Signing.local.xcconfig` with your own certificate — the
steps are in `Signing.xcconfig` — which is what you want if you intend to run the
app: the App Group is how the widget gets its data, and access to another app's
keychain item is tied to the signature. Note that a signature the system does not
recognise changes on every rebuild, so macOS asks for your keychain password each
time.

Or build it unsigned, which is what the release workflow does when no certificate
is configured:

    xcodebuild -project Softcap.xcodeproj -scheme Softcap -configuration Debug \
      -derivedDataPath build CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build

That compiles and produces `Softcap.app`. Entitlements are not honoured without a
signature, so the App Group is not available and the widget has nothing to read.

## How it is put together

The logic lives in `Packages/Core` and does not depend on AppKit, so it ports to
iOS unchanged. The app in `App/` is a thin SwiftUI layer on top of it.

| Module | Responsibility |
|---|---|
| `ProviderKit` | limit models, shared HTTP transport, OAuth primitives and provider protocols |
| `ClaudeProvider` | Anthropic API requests, OAuth sign-in |
| `CodexProvider` | OpenAI browser sign-in, live usage and local session files |
| `Credentials` | credentials in the keychain |
| `Monitoring` | polling, ordering, threshold notifications |
| `Preferences` | settings and their defaults |
| `StatusUI` | shared views and translations, used by window and widget alike |
| `Updates` | the release feed, the download and the bundle swap |
| `Diagnostics` | describing a failure, scrubbed, to the collector |

**`Core` carries no text meant to be read.** Models return identifiers and
numbers; labels are assembled by the UI layer. `ProviderFailure.diagnostic` is
the exception and is English on purpose — it goes to the log, while the interface
shows a translated sentence in its place.

`CoreHasNoHumanStrings` holds the rule from two directions: no literal in any
model module is written in a non-Latin script, which is the shape the rule breaks
in when somebody works in another language; and no model module reaches for
`Localization`. The second is the exact one — a label has to be translated to be
shown, so a model that can translate is a model that holds one. Neither can catch
an English label directly, and nor could any check: "profile not parsed" and
"almost exhausted" are the same shape to a scanner and opposite in kind.

## Where the data comes from

**Claude** — live, from `api.anthropic.com/api/oauth/usage`.

**Codex** — accounts added through the browser read current limits from
`chatgpt.com/backend-api/wham/usage`. This is a usage request, not an inference
request, and sends no prompt. Each request includes the account's own access
token and ChatGPT account identifier.

The local account in `~/.codex/auth.json` is still detected. Without a browser
grant, its readings come from `~/.codex/sessions`, watched with FSEvents. Every
surface shows when that snapshot was taken. Adding the same account through the
browser replaces its local row with live usage; hiding it hides both sources.
Softcap never writes `auth.json` or refreshes a Codex CLI token.

See [authentication architecture](docs/authentication.md) for protocol details,
credential compatibility and the test commands.

## What the app sends back

When something fails — a sign-in, an update check, an install — the app posts a
description of the failure to a collector the author runs at
`sentry.softcap.app`. It is on by default and switched off in **About and data**.
Nothing is sent from a debug build: `startReporting` is not compiled into one, so
there is no reporter to enable rather than a flag holding one back.

What leaves is a level, a category, one English sentence and the failure's type.
No screenshot, no view hierarchy, no request log, no device identifier; the
collector drops the reporting address at ingest rather than storing it.

Every string first passes `Scrubber`, which removes home directories, mail
addresses, anything matching a key's prefix, JSON web tokens, and any value
whose neighbouring word calls it a token, a secret, a password or a key. It is
written to over-redact — a report missing a detail is a nuisance, a report
carrying a refresh token is an incident — and `ScrubberRemovesWhatItMustNotSend`
tests it against the exact shapes that would break it, assembling its fixtures at
runtime because `NoPersonalDataInTheRepository` forbids writing a credential
shape or a home path into this repository even as test data.

The reporter builds no request of its own. It goes through `HTTPClient` like
every provider does, because `NothingElseLeavesYourMac` holds that exactly one
file in this project turns a URL into traffic — and the list of hosts beside that
rule is only worth reading while that stays true.

## Several Claude and Codex subscriptions

The account currently signed in to Claude Code is **read-only** here: the app
never refreshes its token, because a rotated refresh token would sign the CLI
out.

While an account is active, the app keeps a copy of its refresh token — taken on
every poll, which is the only moment it can be taken. When you move to another
subscription with `/login`, the previous one stays visible: the app refreshes it
with that copy, which does not disturb the CLI.

**The app has to be running when you sign in.** An account that was active only
while it was closed leaves nothing behind, and once `/login` moves the CLI on,
that account's token is out of reach — the row says "Sign-in required" until you
sign into it again with the app open. Anthropic also rotates a refresh token on
every use, so a copy the app took can be invalidated by the CLI refreshing the
same account afterwards; the app clears a copy the server has rejected rather
than retrying a dead credential, and the row says the same thing.

Choose **Add account… → Claude Code** or **OpenAI Codex** in Accounts settings
or the menu bar context menu. A browser opens and the password is typed only
there. Codex uses the ChatGPT subscription sign-in. Each saved account has an
independent grant in Softcap's keychain item, and its first access token is kept
with the server-reported expiry so the first poll does not rotate it again.

An account needing a new grant has a **Sign in…** button for its provider.
Forgetting an account removes only Softcap's saved credentials; CLI sign-ins are
left alone. A Codex account still signed into the CLI may remain as a local row.

### The one permission it needs, and how to stop needing it

Reading the account Claude Code is signed into means reading a keychain item
another app owns, and macOS asks before allowing that. The app will not raise
the dialog by itself: `SecItemCopyMatching` blocks until it is answered, and a
dialog raised by a five-minute timer is one nobody is looking for — an
unanswered one froze the app for eighty-four minutes while this was being built.

So a poll asks for no dialog, and the Accounts screen offers a button that asks
properly, with somebody watching.

"Always Allow" is worth choosing, and worth knowing the shape of. macOS ties the
grant to the item, and Claude Code rewrites that item every time it refreshes its
token — about every eight hours, and more often on a machine running several
sessions at once. The grant goes with it and the dialog comes back. That is not a
fault in either program; it is what reading another app's keychain item costs.

An account added through the browser with "Add account…" does not pay that cost.
It holds a grant of its own: the token is refreshed directly, Claude Code's item
is never opened on its behalf, and signing into that account with `/login` will
not quietly replace its credential with a copy of the CLI's. No dialog can appear
for such an account again.

Once every account has been added that way, the app stops opening Claude Code's
item at all — `CredentialStore.dependsOnCLI()` is what decides. Before that it
still asks at setup, where the prompt buys something real: the account you are
already signed into, without signing in a second time.

## Settings

Opened from the limits window, from the status item's context menu, or with ⌘,.

Eight sections: accounts, statistics, appearance, notifications, polling and
launch, updates, services, about.

**Language** — ten languages including Arabic with right-to-left layout.
Switches immediately, no restart. Follows the system by default.

**Appearance** — system, light or dark.

**Order** — least loaded first, by name, or custom. Choosing **Custom** opens a
small account list: drag rows to arrange them, with changes saved and applied
immediately. **Arrange accounts…** opens it again. Switching to automatic sorting
keeps the saved arrangement, new accounts follow the saved ones, and failed readings do
not move accounts out of their chosen positions.

**Minimal window** — the limits window as a list: one line per account, and
colour only where a limit is close. The heading and the named buttons go; the
three actions stay as symbols, and what the row stopped saying — the service,
the plan, the date a stale reading was taken — moves into its tooltip. Which
limit the line shows is the one **Primary window** names, and that setting
therefore does two jobs here. Off by default, and in the status item's menu as
well as in settings.

Settings live in `~/Library/Preferences/app.softcap.Softcap.plist`.
Accounts the app gathered itself are in the Keychain under the service
`StatusChecker-accounts` — the old name, kept through the rename so that nothing
already stored is lost.

## VoiceOver

An account is one element, not eight: it is read as a sentence — "Claude,
name@example.com, Max 20x. Five-hour: 23% used, 3 hours 39 minutes left." The
bars, the tick and the ring say nothing out loud, and colour — the only place
urgency is encoded — says nothing either, so the sentence carries it in words.

Durations are spelled out by the system rather than the catalogues: "3h 39m"
reads as letters, and whole words need plural forms that differ per language.

## Statistics

One chart, one line per account, over the last week or month.

It draws the **weekly** window. Over a month the five-hour one resets a hundred
and forty-four times, which is a comb rather than a chart; the weekly window
resets once a week, so each tooth is one week's allowance and a flat top is an
account that ran out.

Colour means *which account* here and *how loaded* everywhere else, so the two
scales do not collide: identity is cool — blue, violet, teal — and load stays
warm.

A break in a line is a stretch with nothing measured — usually the app not
running. Drawing straight across it would claim a reading nobody took. An account
you hide is left out of the chart rather than drawn up to the moment you hid it,
which would read as an outage.

Readings are kept as the app polls, sparingly: one when the figure moves by a
point, at most every five minutes, and one every half hour regardless so a flat
line stays distinguishable from a gap. They live in `history.json` beside the
snapshot and are pruned after 35 days.

Codex is the exception to starting empty: it has been writing its own readings
into `~/.codex/sessions` for weeks, and they are imported on launch. Claude has
no equivalent — its API answers for the present only — so those lines begin the
day the app is first run.

## Widgets

All four sizes on the Mac desktop; on iPhone the home screen and two of the three
shapes a lock screen allows — the circle and the rectangle, not the inline one
beside the clock, which has room for a few words and would have to leave out
either the figure or whose it is. The small one shows the busiest account large;
the others show a list of as many rows as fit. The account row is the same one
the window uses.

Data arrives from the app through
`~/Library/Group Containers/ABCDE12345.group.app.softcap/snapshot.json`: a
widget is a separate process and does not reach the network itself.

## iOS

`iOS/` holds a phone app built on the same shared modules: the account row comes
from `StatusUI`, so the Mac window, both widgets and the phone cannot drift
apart.

Claude and saved Codex browser accounts are queried directly using credentials
in the iCloud keychain, so the phone does not need the Mac to be awake. Local
Codex session files remain Mac-only. Hidden accounts and disabled services are
excluded from phone polling too.

Signing is disabled for that target, so it builds and runs in a simulator with no
certificate.

## Not done yet

Providers for Cursor, GitHub Copilot and Gemini CLI — there is
already room for them in the Services section, but the Cursor token on this
machine has expired and Gemini has no credentials at all, so there is nothing to
verify an implementation against.

## The site

`site/` is the landing page at <https://softcap.app/> — one self-contained HTML
file, an SVG icon, and the preview image shown when the link is shared.

It offers the same three appearances the app does. The switch is three radio
buttons and `html:has(:checked)` setting `color-scheme`; every colour is a
`light-dark()` pair, so there is one definition per colour and no script — which
is what keeps the page's Content-Security-Policy at `default-src 'none'`.

    site/check-widths.sh    # render at 320-1920 px and fail on any overflow

    site/deploy.sh          # ship it and verify over HTTPS
    site/deploy.sh --status # is the server serving this checkout? (no ssh needed)

The host runs everything in Docker behind `kamal-proxy`, which terminates TLS and
routes by the Host header. The site is stock Caddy with the files bind-mounted,
on the `kamal` network so the proxy can reach it by container name. It takes the
host from whatever the domain resolves to; `SOFTCAP_HOST` overrides that.

`deploy.sh` refuses to report success on anything it has not seen. Before
shipping it rebuilds `og.png` and the favicon if either is older than what it is
made from, runs the width check, and refuses a missing or truncated file. After
shipping it restarts the container — an edited `Caddyfile` is bind-mounted, so
the file changes and the running server does not — registers the route, and then
checks four things over HTTPS:

- every served file by SHA-256 against the live URL, not by status code: a 200
  proves something is there, not that it is the thing that was sent;
- `Cache-Control` on the URLs people actually request, because the rule had been
  written for `/index.html` and everybody arrives at `/`;
- that the domain reached `kamal-proxy`'s saved state, since a route held only in
  memory serves perfectly until the host reboots;
- that the container's restart policy is what the compose file says.

Every one of those runs *after* the files are already live, so a deploy that
fails its own verification used to leave the broken page up with no way back but
forward — which happened once, when a digest check found six mismatches after the
transfer. The version that was live is now copied to `dist.prev` before anything
is replaced, and the failure message names the way back:

    site/deploy.sh --rollback

`--status` is the one part of that script needing no ssh: it fetches each served
file and compares it with the one here. The repository can move ahead of the
server without anything saying so — ssh to the host stopped answering for two
runs while it went on serving the site perfectly, and the deploy refused, exactly
as it should have — and until that check existed the drift was visible only to
somebody who thought to look.

`prev/` holds all three things a deploy replaces — the pages, the `Caddyfile` and
the compose file. The first version kept only the pages, which missed the worse
of the two failures: a Caddyfile that does not parse stops the container, and a
site that is down is worse than a site that is wrong.

The rollback restores the contents of `dist` rather than swapping the directory:
it is bind-mounted into the container, so a rename would leave Caddy serving the
old directory under its new name. It refuses a snapshot holding fewer files than
the site serves, because restoring an incomplete one would take the site down; it
names the configuration it put back, or says plainly that the snapshot held none;
and it checks that every URL answers and the page is whole, rather than checking
digests against this checkout, which after a rollback are *supposed* to differ.

The favicon is generated too — `site/make-favicon.sh` renders `icon.svg` at 16,
32 and 48 px and packs them into one `.ico`. Below 40 px it drops the inner ring
and thickens the outer one, which is what the app's own icon generator does: two
concentric strokes a few pixels apart merge into a smudge rather than reading as
two rings.

The preview image is generated, not drawn — `deploy.sh` re-renders it whenever
`og-template.html` is newer, so it cannot be forgotten:

    chrome --headless=new --window-size=1200,630 \
      --screenshot=site/og.png site/og-template.html

A test requires the template to repeat the page's headline, accounts and
released-or-not status, which closes the loop: changing the page forces changing
the template, which makes the template newer than the image.

Nobody is counting visitors — there is no analytics on the page. Caddy logs
requests to its own stderr, so `docker logs softcap-site` is where traffic shows
up if anyone wants to look.

## Before committing

    tools/install-hooks.sh    # once per clone

That points git at `tools/hooks`, which runs the whole suite before every commit
— about four seconds. The ten checks in `NoPersonalDataInTheRepository` get
their own message, because theirs is the one failure that cannot be fixed
forward: the value is in the history from the moment it lands. They read every text file kind the repository
has, which they did not: the list was the seven a leak had happened in, and left
out `.entitlements`, `.plist` and `.xcconfig` — where the two most specific
checks, for an Apple team identifier and a foreign bundle identifier, look for
their subject. They refuse a mail address outside the reserved example domains, an
account identifier from a running instance, anything shaped like a credential, an
absolute path from one machine, that machine's own name or login, a path into a
neighbouring checkout, a routable host address, the Apple team identifier, and a
bundle identifier that is not this project's. The tenth reads none of those
files: it asks git for every commit message and holds the history to the same
rules, because a value written into a message is in no file the other nine walk.

It began as those nine alone and ran one suite out of sixty-eight, which is how a
commit went out with two tests failing in another. It runs everything now, and
refuses on any red — `git commit --no-verify` is there for a deliberate one.

The same checks are in the test suite. The hook exists because the suite ran too
late twice — both leaks were prose describing a live run, committed before the
next `make test` saw them — and the four beyond the first four were added after a
rewrite of the whole history found what the first four had no opinion about. The
ninth came after an entry describing that rewrite quoted the old bundle prefix
back into the repository the rewrite had just removed it from. The tenth came
after the same prefix was found still sitting in a commit message from that
week, where the entry had been fixed and no check had ever looked.

## Proving a guard

Most of the tests here exist to catch a specific mistake, and a test that would
not catch it is worse than none: it reads as coverage. The way to know is to
break the thing on purpose and watch the check go red.

    tools/mutate <file> <old> <new> -- <command>

Doing that by hand failed six ways in this repository, and every one of them
looked exactly like the guard passing — a `sed` that matched nothing because the
phrase wraps across a line, a `--filter` naming a test that does not exist,
`ssh $OPTS host` becoming one argument because zsh does not word-split. So the
tool makes a mutation that changes nothing an error rather than a quiet no-op,
restores from a copy rather than through git — `git checkout --` threw away
uncommitted work twice — and refuses to run at all on a file that is not clean.

It exits 0 when the check failed, which is the outcome you want; 1 when the check
passed with the file broken, which means it is not guarding that; and 2 when the
mutation could not be made.

The hook has two floors of its own, for the same reason: a run that examined
nothing exits zero and prints a line that reads like success. The personal-data
suite has to appear by name in the results, and the run has to have examined a
hundred tests against the four hundred there are. The count is read with `sed`
and checked for being a number before it is compared — written with `grep -oE` it
captured the ANSI colour codes around the digits, the comparison errored, and an
erroring test inside an `if` is simply false, so the floor never fired.

## Documents

    tools/decisions-index [substring]   # every heading, dated, with its line

- `docs/DECISIONS.md` — the decision log: what was decided and why, and where
  there was one, what it cost. **Append-only.** An entry is never rewritten,
  because the reasoning in it was true when it was written; where a later one
  found an earlier one wrong it says so, and two of those begin *Correction*.
  Chronological, so the way to find something is to search the headings —
  `tools/decisions-index` lists all two hundred of them with the date each was
  written and the line it starts at. Forty-two carry their own date in the
  heading and are believed; the rest are dated from the commit that added them,
  which is why the tool reads git rather than being a file that would drift.
- `docs/superpowers/specs/` — design documents, marked approved and implemented.
  Their "out of scope" sections predate the iOS app, the widgets and the
  statistics screen, and the module table in the monitor design still calls the
  threshold code `ThresholdNotifier`; the type is `ThresholdTracker` and the
  sending it was named for happens in `AppModel`.
- `docs/superpowers/plans/` — work plans, all carried out. There is a note in
  that directory saying what each one built and where the current record is.
- `docs/design/` — two mock-ups in Russian, made before the app was written and
  kept for the reasoning in them. The window one worked out three row layouts and
  the spec says which was chosen; the settings one draws a pane set the app no
  longer has — it predates the statistics screen, and the hot keys ended up
  inside other panes.
- `tools/add_strings.py` — filling the translation catalogues.
