# Decision log

Each entry: what was decided, why, and what it cost. Entries are never rewritten
after the fact — if a decision is reversed, a new entry is added referring to
the old one.

Dates are YYYY-MM-DD.

---

## 2026-08-30 · The active Claude account is read-only

**Decision.** The account whose refresh token matches the one currently in the
`Claude Code-credentials` keychain item is never refreshed by the app. Its
access token is re-read before every poll.

**Why.** Refreshing may rotate the refresh token on the server side. The CLI
would then hold a stale token and get signed out — an app for watching limits
would have broken the tool it watches.

**Cost.** While an account is active, the app depends on the CLI keeping the
token fresh. If the CLI is not run for weeks, the token expires.

---

## 2026-08-30 · Subscriptions accumulate through a token copy, not a separate sign-in

**Decision.** While an account is active in the CLI, the app copies its refresh
token on every poll. When the user moves to another subscription, the previous
one stays visible — the app refreshes it with that copy.

**Why.** A dedicated OAuth sign-in was the original plan, but its parameters
could not be confirmed: `claude.ai/oauth/authorize` answered `403`. Accumulation
requires nothing beyond what the user already does (`claude /login`) and does not
conflict with the CLI: an inactive account is no longer used by it.

**Cost.** An account appears in the list only after being signed into at least
once on this machine. Lifted later — see the browser sign-in entry.

---

## 2026-08-30 · Codex data is a snapshot, and the interface says so

**Decision.** Codex limits are read from local session files in
`~/.codex/sessions/**/*.jsonl`. The snapshot's age is shown as a badge
("data from 28 Aug").

**Why.** A direct request to `chatgpt.com/backend-api/codex/usage` answers `403`
— that route is closed. The session files carry a `rate_limits` event with
percentages and reset times, and reading them needs no network at all.

**Cost.** The data goes stale until Codex next goes online. Showing the age is
more honest than passing a snapshot off as the current state.

---

## 2026-08-30 · The menu bar timer follows the busiest window

**Decision.** The status item shows the time until the reset of whichever window
is closest to exhaustion, not the reset that comes soonest.

**Why.** For a free account the reset time means nothing. The question the icon
answers is "how long until the one that ran out comes back".

---

## 2026-08-30 · Signed with Apple Development, not ad-hoc

**Decision.** `CODE_SIGN_IDENTITY` is a real developer certificate rather than
ad-hoc. The concrete values live in `Signing.local.xcconfig`, which is not
tracked — otherwise the project only builds for its author.

**Why.** macOS ties access to another app's keychain item to the app's
signature. An ad-hoc signature changes on every rebuild, so "Always Allow" was
never remembered and the password was asked again and again.

**Cost.** Building requires a certificate in the keychain. Another machine needs
its own `Signing.local.xcconfig` — the template and steps are in
`Signing.xcconfig`.

---

## 2026-08-30 · Monochrome glyphs instead of coloured icons

**Decision.** Settings section icons and service logos are stroked symbols in
the label's colour, with no coloured backplates.

**Why.** Colour already carries meaning in the limits window: green, yellow,
orange and red encode load. Brand colours next to them dilute that language and
both signals weaken.

---

## 2026-08-30 · Browser sign-in: parameters taken from Claude Code's own constants

**Decision.** "Add account…" performs OAuth with PKCE. Endpoints: authorize
`platform.claude.com/oauth/authorize`, token
`platform.claude.com/v1/oauth/token`, client_id `9d1c250a-…`.

**Why.** The parameters were not guessed: they were read from the constants of
the installed Claude Code and verified live — authorization answers `200` and
serves the sign-in page. This also revealed that **the domains had changed**: the
former `claude.ai/oauth/authorize` answers `403`, which is why the first attempt
failed. `AnthropicTokenRefresher` was moved to the current endpoint.

**Cost.** The parameters belong to another application and may change again.
They are collected in a single `OAuthEndpoints` type so the edit is in one place.

---

## 2026-08-30 · Custom NSStatusItem instead of MenuBarExtra

**Decision.** The menu bar item is created manually through `NSStatusItem`.

**Why.** `MenuBarExtra` offers no way to configure the right click, and a context
menu is expected behaviour for menu bar apps.

**Cost.** More code than a declarative scene. In exchange, full control — and the
`Label`/`labelStyle` workaround used to fix label alignment went away.

---

## 2026-08-30 · The settings window is built from HStack, not NavigationSplitView

**Decision.** The settings sidebar is a plain `VStack` of buttons inside an
`HStack`.

**Why.** `NavigationSplitView` inside a `Settings` scene renders an empty window
— no list, no content. Verified by substituting a plain text view: it *did*
render, so the navigation was the empty part, not the scene.

**Cost.** No system sidebar behaviour (collapsing, drag-to-resize). A settings
window does not need it.

---

## 2026-08-30 · Settings are opened through the app menu item

**Decision.** `SettingsWindow.open()` finds the settings item in the app menu and
performs it.

**Why.** `sendAction` with the private selectors (`showSettingsWindow:`,
`showPreferencesWindow:`) never reaches the scene — the window did not appear.
The `Settings` scene creates a working menu item itself, and that one fires.

Separately: the app is marked `LSUIElement`, so it runs as an agent without a
Dock icon and does not come forward on its own. Without explicit activation the
window was created but ended up behind other windows — indistinguishable from a
dead button.

**Cost.** A dependency on the menu item. Matching by title was later found to
break in eight languages — see the critical findings entry.

---

## 2026-08-30 · Core carries no human-facing strings

**Decision.** All labels were removed from `Packages/Core`: `LimitWindow.label`,
the `.title` properties on settings enums, pre-built time strings.
`formatRemaining` was replaced by `RemainingTime`, a struct of days, hours and
minutes. `ProviderFailure.message` became `diagnostic`, meant for the log; the
interface text is built from `kind`.

**Why.** 35 of 105 interface strings lived in models. That hurt twice: the
language could not change without a rebuild, and `Core` could not move to iOS
with a different string set. Unit order and plural forms depend on the language
anyway — Arabic has six plural categories, Indonesian has one.

**Exception.** `ProviderID.title` stays: `Claude` and `Codex` are brand names and
are not translated.

**Cost.** A breaking change for every consumer of the models. In exchange there
is now a guard test that scans the sources and keeps the rule from eroding.

---

## 2026-08-30 · The account row moved to a shared module

**Decision.** `AccountRow` and everything that draws limits moved out of `App/`
into a `StatusUI` module inside `Packages/Core`.

**Why.** The widget must show exactly what the window shows. A duplicated view
drifts on the first edit — you fix the window and forget the widget. The module
depends only on SwiftUI, without AppKit, so it ports to iOS too.

**Cost.** A shared module cannot use app-level types (`AppModel`,
`PreferencesModel`) — views take ready data as parameters. Which is for the
better: they became testable in isolation.

---

## 2026-08-30 · The widget receives data through a shared file, not an App Group

**Decision.** The snapshot is written to
`~/Library/Application Support/dev.example.StatusChecker/snapshot.json`.

**Why.** An App Group looks more correct and was the first choice, but it
requires a provisioning profile, which in turn requires the machine to be
registered in a developer account: the build failed with `Device "laptop" isn't
registered`. For an app built and run locally that is a needless barrier. Neither
the app nor the widget is sandboxed, so the shared path is reachable by both.

**Cost.** If the app ever ships through the App Store, sandboxing becomes
mandatory. Then a single property, `SharedStore.url`, changes — the rest of the
code does not know where the file comes from.

---

## 2026-08-30 · The widget adapts by capacity, not by separate layouts

**Decision.** One set of views for every size. The small one shows the busiest
account large; the others show a list of as many rows as fit (2 / 6 / 8). The
account row is the same `AccountRow` the window uses.

**Why.** A separate layout per size drifts from the window on the first edit.
Only the capacity differs.

**Important detail.** When accounts do not fit, "+N more" is shown at the bottom.
Truncating silently would make the user believe there are fewer accounts than
there are.

---

## 2026-08-30 · A custom translation layer instead of the system AppleLanguages

**Decision.** The language is stored in settings; the app holds a `Bundle` for
the chosen language and serves strings through `Localization`. Root views carry
`.id(loc.language)`, so switching triggers a full redraw.

**Why.** The system `AppleLanguages` mechanism requires an app restart. For a
menu bar monitor that is unacceptable: the user changes the language and expects
the label to follow.

**Cost.** Strings are fetched through `loc("Key")` rather than
`NSLocalizedString`. In exchange the switch is instant, and the keys stay English
phrases — a missing translation shows readable text.

---

## 2026-08-30 · Catalogue keys are English phrases

**Decision.** `loc("Refresh")`, not `loc("button.refresh")`.

**Why.** A missing translation shows the key. An English phrase reads; an
identifier does not. The English catalogue is also identical to the key set and
needs no separate upkeep.

**Cost.** Editing English text changes the key in all ten catalogues. Caught by
the test that compares key sets.

---

## 2026-08-30 · Translation completeness is enforced by tests

**Decision.** Three checks: every language has a catalogue, key sets match
English, and format specifiers (`%@`, `%lld`) have not diverged.

**Why.** A missing translation looks like an English phrase among Russian ones —
impossible to spot by eye across nine languages. A diverged specifier is worse:
the account name simply vanishes from the message.

**Finding.** SwiftPM lowercases localization directory names: `zh-Hans.lproj` in
the sources becomes `zh-hans.lproj` in the bundle, and an exact lookup misses it.
The lookup now tries both spellings.

---

## 2026-08-30 · The settings owner applies the language, not two places at once

**Decision.** `Localization.use()` is called only from `PreferencesModel`, in
`load()` and `update()`.

**Why.** The language used to be applied by both the app delegate and the
settings scene. The scene is created before settings finish loading, so it
overrode the delegate with the default value. The log showed an alternating
`ar → system → ar → system`, while the screen stayed English with Arabic
selected.

**How it was found.** By measurement, not reasoning: the translation mechanism
passed its tests, the catalogue was in place, and a probe at runtime returned
correct Arabic — so the fault was in call ordering, not lookup. A log of `use()`
calls showed the alternation.

**Lesson.** A setting applied from two places will eventually race. There must be
one owner.

---

## 2026-08-30 · Catalogues are filled by a script, not by hand

**Decision.** `tools/add_strings.py` reads JSON with translations and appends
missing keys to all ten catalogues. Existing keys are left alone, so it is safe
to re-run.

**Why.** Ten files per new string is a guaranteed source of divergence. The
script plus the key-set test close that off entirely.

---

## 2026-08-30 · Cursor and Gemini providers postponed: nothing to verify against

**Decision.** Not implemented until there are live credentials on the machine.

**Why.** The Cursor token in `state.vscdb` expired 102 days ago — three
authorization schemes against `cursor.com/api/usage` all returned `401`, and
"wrong scheme" cannot be told apart from "dead token". Gemini has no credentials
at all: `~/.gemini` holds only configuration from November.

A provider could be written from documentation, but not verified. An unverified
provider is worse than a missing one: it will quietly show zero instead of
admitting it has no data.

**To resume.** Launch Cursor and sign in; `cursorAuth/accessToken` will refresh
and the scheme can be settled in one pass. Room for both services already exists
in the Services section.

**Found along the way.** Cursor keeps `cursorAuth/*` keys in `state.vscdb`:
access token, refresh token, email and subscription type (`enterprise`). Enough
to identify the account without any network.

---

## 2026-08-30 · Live Codex polling rejected: it spends the very limit it watches

**Decision.** Codex stays a snapshot from session files. No request is made to
`chatgpt.com/backend-api/codex/responses` for the sake of headers.

**Why.** The rate limit headers (`x-codex-active-limit`, `x-codex-credits-*`,
`x-codex-rate-limit-reached-type` — names found in the CLI binary) arrive only on
a **successful** request. An incomplete request returns `400` with none of them.

So polling every five minutes means 288 requests a day, each spending the quota
being watched. A monitor that consumes the observed resource is pointless: it
distorts what it measures.

**Instead.** Snapshot accuracy is improved by watching the session files: as soon
as Codex writes a new `rate_limits` event, the app updates. The data is fresh
exactly when Codex is in use — and when it is not, the limits are not moving
either.

**Cost.** If Codex has not run for a week, the reading is a week old. That is
shown honestly by the age badge and matches reality: an unused subscription is
not being spent.

---

## 2026-08-30 · The Codex file watcher uses FSEvents, not DispatchSource

**Decision.** `SessionWatcher` watches `~/.codex/sessions` through FSEvents and
triggers a refresh when Codex appends an event.

**Why FSEvents.** The first implementation used a `DispatchSource` on a directory
descriptor and silently did nothing. Codex files live in date subdirectories
(`sessions/2026/08/30/…`), and `DispatchSource` only watches the directory
itself, missing nested writes. FSEvents watches recursively.

**How it was found.** Tests on a flat directory passed, but a live check on the
running app showed the snapshot unchanged. A test for writes into a nested
directory now prevents a return to non-recursive watching.

**Debouncing.** Codex writes events in bursts, so one user action fires several
times. The notification is deferred a second after things go quiet, otherwise the
app would re-read the files ten times over.

---

## 2026-08-30 · Three critical findings from self-review

A review of the whole branch found 14 problems. Three of them broke advertised
functionality, and two were introduced by me.

**Notifications never worked at all.** `requestAuthorization` was never called
anywhere, and the error from `add()` went into a discarded closure. The system
silently rejected every notification — the entire Notifications section,
`ThresholdTracker` and quiet hours were dead in practice. Permission is now
requested on first launch, and the error goes to the log.

**The notifications toggle disabled itself.** `.disabled` was applied to the whole
form, including the "Notify" toggle. Once notifications were turned off, there
was no way to turn them back on from the interface. Everything but the toggle is
disabled now.

**Settings could not be opened in eight languages out of ten.** The menu item was
matched by title ("settings" or "настройк"), but the title comes from the system
localization: "Réglages…", "设置…", "الإعدادات…". The item is now found by its ⌘,
shortcut and the window by its content type. Neither depends on language.

**Lesson.** All three follow from testing in one language and one scenario.
Localization breaks more than text: it breaks code that leans on text.

---

## 2026-08-30 · The remaining eleven findings from self-review

**Refreshes were dropped.** `refresh()` discarded a call while a poll was running.
The Codex file watcher landed exactly in that window, so new readings waited for
the next tick — up to five minutes. This defeated the whole point of instant
updates. A repeat call is now remembered and run afterwards.

**The hot key did not work until settings were opened once.** Registration lived
in the `Settings` scene, which SwiftUI creates lazily. Moved to app launch.

**A race and a dangling pointer in the watcher.** `FSEventStreamContext` held
`passUnretained`, so a callback in flight outlived the object. On top of that
`debounce` and `stream` were touched from two threads. The reference is now
retained with a matching release, and the state sits behind a lock. A lock, not a
queue: `deinit` may run on that same queue, and `queue.sync` deadlocked — the
test crashed with signal 5.

**One bad element invalidated an entire Claude response.** The `limits` array was
decoded as a whole: an unfamiliar shape in one entry failed the decode even
though the legacy fields in the same payload were fine. Entries are now decoded
one by one — the same principle already applied to Codex session lines.

**Manual code entry never worked.** The page shows `code#state`, but the whole
string was sent for exchange. The manual path also had neither a state check nor
a timeout — an abandoned sign-in blocked the button forever.

**The listener leaked** when the port could not be obtained after start.

**The menu bar timer froze** between polls: the remainder was computed once per
poll. A per-second tick was added, as in the window.

**The widget rendered in English.** The language was applied in `onAppear`, but a
widget renders in a single pass — strings and layout direction were computed
earlier. The language is now set when the view is constructed.

**The PKCE generator silently returned zeroes** when `SecRandomCopyBytes` failed,
making the verifier predictable. It now returns `nil` and the sign-in honestly
does not start.

**Launch-at-login looped** on error: the change handler called itself.

---

## 2026-08-30 · Documentation is written in English

**Decision.** README, this log and the specs are in English. Conversation stays
in Russian.

**Why.** Requested on 2026-08-30. The project ships a ten-language interface; its
own documents should not be locked to one language either.

**Cost.** The two work plans in `docs/superpowers/plans/` remain in Russian —
about 6900 lines of already-executed step-by-step instructions. Translating them
buys little: they are a record of work done, not a reference. New plans are
written in English.

---

## 2026-08-30 · The settings window joins the ⌘⇥ switcher while it is open

**Decision.** `SettingsWindow.open()` switches the activation policy to
`.regular`, and it returns to `.accessory` once the last visible window closes.

**Why.** The ⌘⇥ switcher lists regular applications only. As an agent the app was
absent from it, and so was its settings window: once the window lost focus, the
only way back to it was the menu bar icon — which is not where anyone looks for
a window they had open a moment ago.

**Cost.** A Dock icon appears together with the switcher entry.
`NSApplication` has one activation policy for both, so the two cannot be asked
for separately. It is visible only while a window is open.

---

## 2026-08-30 · The settings menu item is searched for in every submenu

**Decision.** `invokeMenuItem()` walks all top-level submenus looking for the ⌘,
item instead of reaching into a fixed index.

**Why.** The code took the app menu to be the second item of `NSApp.mainMenu`,
assuming the first belongs to Apple. It does not — the Apple menu is the
system's and is not part of `mainMenu`, whose first item is the application
menu. Index 1 is "Edit", which has no ⌘, and the settings never opened: the
call fell through to `NSSound.beep()`. This survived the language fix of the
previous entry, because that fix corrected how the item is recognised, not where
it is looked for.

**Cost.** A full pass over the menu instead of one lookup — negligible, and it
no longer depends on the order SwiftUI builds the menu in.

---

## 2026-08-30 · Core builds for iOS; only the Codex file reader is Mac-only

**Decision.** `Packages/Core` declares both platforms. `SessionWatcher` and
`RealCodexFileSystem` are wrapped in `#if os(macOS)`; everything else — models,
parsing, providers, credentials, monitoring, shared views and translations —
compiles for iOS unchanged.

**Why it worked.** The rule that Core carries no human-facing strings and no
AppKit turned out to be exactly what portability needed: six of the seven modules
built for iOS with zero errors on the first attempt. Only `CodexProvider` failed,
on `FSEventStreamRef` and `homeDirectoryForCurrentUser` — both genuinely absent
from iOS.

**Why the split is along that line.** Parsing a Codex session file is pure logic
and useful anywhere; reading `~/.codex` is not. On iOS the phone receives a
snapshot prepared by the Mac rather than reading local files, exactly as the
monitor spec anticipated. So the parser is shared and the reader is not.

**Cost.** `CodexUsageProvider` has no default initializer on iOS — the caller
must supply a source. That is honest: there is no local source to default to.

---

## 2026-08-30 · The iOS app reuses the row, and omits Codex

**Decision.** `iOS/` is a phone app on the same shared modules. The limits list
draws `StatusUI.AccountRow` — the same view the Mac window and the widget use.
Codex is not offered on iOS at all.

**Why the shared row.** Three surfaces showing the same data cannot be allowed to
drift. One view means a fix in the window reaches the phone and the widget for
free — which is what the shared module was created for.

**Why no Codex.** Its data lives in local session files on the Mac; the phone has
no access to them. An empty Codex row would look like a limit at zero rather than
like missing data, which is worse than not showing the service.

**Cost.** The phone shows Claude only. That is honest, and the empty state points
at the one thing that helps: signing in on the Mac, from where accounts reach the
phone through the keychain.

**Signing.** Disabled for this target — it builds and runs in a simulator without
a certificate. A real device will need one.

---

## 2026-08-30 · The iOS widget uses an app group; macOS keeps its file

**Decision.** `SharedStore.url` differs by platform: a path under
`Application Support` on macOS, an app group container on iOS.

**Why the difference is forced, not chosen.** On iOS every app and extension gets
its own container — a shared path simply does not exist, and sandboxing is not
optional. An app group is the only way across. On macOS the group would need a
provisioning profile and a registered machine, while neither the app nor the
widget is sandboxed, so a plain path works and costs nothing.

**Signing in the simulator.** The iOS targets were first built with
`CODE_SIGNING_ALLOWED: NO`, which meant entitlements were never embedded and the
group container did not exist. Ad-hoc signing (`CODE_SIGN_IDENTITY: "-"`) is
enough: the container appears and the app writes into it. A real device will
still need a real profile.

**Verified.** The phone app wrote its snapshot into the group container on
launch, so the channel to the widget works end to end.

---

## 2026-08-30 · The lock screen shows one number

**Decision.** The iOS widget supports `accessoryCircular` and
`accessoryRectangular` in addition to the home screen sizes. The circular one is
a gauge with a single figure.

**Why.** A lock screen accessory has room for one thing, so it shows the figure
that decides whether you can work at all: the busiest window across every
account. The same principle as the menu bar timer on the Mac.

**Refresh interval.** Fifteen minutes rather than the Mac's five: iOS budgets
widget refreshes tightly and asking too often only makes the system refuse. The
countdowns are recomputed on every render regardless, so nothing looks frozen.

---

## 2026-08-30 · The macOS widget uses the app group too — a file never worked

**Decision.** `SharedStore` uses an App Group container on both platforms. On
macOS the widget extension is sandboxed and both targets carry
`com.apple.security.application-groups`. This reverses two earlier entries: "The
widget receives data through a shared file, not an App Group" and the macOS half
of "The iOS widget uses an app group; macOS keeps its file".

**Why.** The macOS widget had never been available at all: it was absent from
`pluginkit -m -p com.apple.widgetkit-extension`, so it could not appear in the
widget gallery and could not be added to the desktop. macOS refuses to register a
widget extension that is not sandboxed, and it refuses silently — nothing in the
log, nothing in the build. The extension carried only `get-task-allow`.

Adding `com.apple.security.app-sandbox` registers it immediately — confirmed by
re-signing an installed copy by hand before changing anything in the project. But
a sandboxed extension resolves `Application Support` inside its own container, so
the shared path the app writes to becomes invisible to it. The two facts together
leave the app group as the only channel.

**The premise of the reversed entries was false.** They rested on "neither the app
nor the widget is sandboxed on macOS", which the widget is not free to choose.
They also assumed an app group needs a provisioning profile and a registered
machine. It does not, on macOS: manual signing with a real team certificate is
enough, and the Xcode account on this machine has a stale token (`missing
Xcode-Token`) yet the container works. The `-allowProvisioningUpdates` in the
Makefile, added for app groups, is doing nothing.

**Cost.** The group identifier is spelled differently per platform — macOS wants
the team prefix (`ABCDE12345.group.dev.example.StatusChecker`), iOS does not — so
the team ID is now hard-coded in `SharedStore`. The old snapshot under
`~/Library/Application Support/dev.example.StatusChecker/` is orphaned.

**Verified.** After the change the extension registers from the build folder —
no install into `/Applications` needed — and the app writes its snapshot into
`~/Library/Group Containers/ABCDE12345.group.dev.example.StatusChecker/`. That
the widget renders that data is not yet observed: it takes adding the widget to
the desktop by hand.

---

## 2026-08-30 · The icon is two rings, generated from code

**Decision.** Two concentric arcs — the outer one the weekly window, the inner
one the five-hour window — in graphite with a single green accent. Generated by
`tools/make_icons.swift` rather than stored as exported images.

**Why generated.** A change becomes a one-line edit and a re-run, and the rule
for small sizes lives beside the drawing instead of in someone's memory. Exported
PNGs would drift from whatever produced them.

**The small-size rule.** Below 40 px the inner ring is dropped and the outer one
thickened. Two concentric strokes cannot be told apart once a ring is a few
pixels across — they merge into a smudge. One honest ring beats two mushed
together.

**The menu bar glyph follows the same shape**, drawn as a template image so the
system tints it for light and dark bars. Its threshold sits at 22 pt, above the
16 pt the menu bar hands out, so there the glyph is a single ring — checked on a
screenshot, an inner ring at that size read as a dot.

**The icon shows fixed values, not live data.** It sits in the Dock even when the
app is closed, so a changing icon would lie. Live state is the menu bar and the
widget's job.

**Worth knowing.** The concept overlaps with Apple Fitness, which also uses
rings. Ours differs by the dark plate and two rings against three coloured ones,
but the resemblance is real and worth a second look before shipping.

---

## 2026-08-30 · Two untested seams closed

A sweep for public types with no test coverage found two that mattered.

**Token refreshing had none.** `AnthropicTokenRefresher` performs the request
that keeps every non-active account alive, and nothing checked it. Six tests now
cover it, including one that asserts the request goes to `OAuthEndpoints.token`:
the domain moved once already, and a regression there would silently break
refreshing for every account except the one signed into the CLI.

**The widget channel had none.** `SharedStore` carries everything the widget
draws — accounts, layout, language — and a mistake there shows up as an empty
widget with no error anywhere. Six tests now cover the round trip, a missing
file, a truncated file, and the fact that rewriting replaces rather than appends.

**A change came with it.** `write`/`read` gained overloads taking an explicit
URL. A test writing to the real `Application Support` would leave traces on
whatever machine ran it; now the exchange is exercised in a temporary directory.
The no-argument versions still use the platform location.

---

## 2026-08-30 · Correcting an earlier entry: the wrong authorize URL

The browser sign-in opened "How will you use the Claude API?" — the Claude
Console page for creating an API account. Nobody asked for that.

**What was wrong.** Claude Code carries two authorize URLs and they lead to
different places: `CONSOLE_AUTHORIZE_URL` (`platform.claude.com`) is the developer
API console, `CLAUDE_AI_AUTHORIZE_URL` (`claude.com/cai/oauth/authorize`) is the
subscription sign-in. This app watches subscription limits, so the second one is
correct. I took the first.

The scope was wrong for the same reason: `org:create_api_key` belongs to the
console. A real subscription token carries
`user:inference user:profile user:sessions:claude_code user:mcp_servers user:file_upload`
— read from the keychain item Claude Code writes. The app never creates API keys,
so asking for that permission was wrong on its own merits.

**And an earlier conclusion was wrong too.** The entry "the domains changed"
claimed `claude.ai/oauth/authorize` was dead because it answered `403`. It is
not: `claude.com/cai/oauth/authorize` redirects straight to it, and the `403` was
Cloudflare turning away `curl`, not the endpoint being gone. The right lesson was
available at the time and I drew the wrong one — a `403` to a command-line tool
says nothing about what a browser gets.

**Lesson.** Two constants with similar names, and no check of where the opened
page actually led. Opening a URL is not the same as verifying it goes somewhere
useful.

---

## 2026-08-31 · Reading the browser return moved into Core

**Decision.** `OAuthCallback` parses both the listener's HTTP request line and a
code pasted by hand. `LoginController` calls it instead of parsing inline.

**Why.** This is where a bug already hid: the manual path sent `code#state` whole
and every exchange failed. Nothing could have caught it — the parsing sat in a
view controller with a live network listener attached, so exercising it meant
performing a real sign-in.

As pure functions the same logic takes eleven tests, including cases the inline
version got wrong or never considered: a bare newline instead of CRLF, an
explicit `error=access_denied`, a favicon fetch reaching the same listener, and a
pasted value with no state at all.

**One behaviour changed.** A favicon fetch is now answered and ignored rather
than treated as a failed return. Before, a browser requesting `/favicon.ico`
could abort a sign-in that was still in progress.

---

## 2026-08-31 · Memory checked: no leak, and a hasty conclusion corrected

**What was measured.** The app had been running for half an hour. Resident memory
across six samples over six minutes: 70.3, 71.1, 70.3, 70.4, 71.3, 70.9 MB — a
spread of one megabyte, no trend. CPU at rest 0.2%. No network descriptors left
open, so the sign-in listener is not accumulating.

**A conclusion I got wrong first.** The opening measurement was a single
before/after pair a minute apart and showed +4.9 MB, which extrapolates to
+292 MB an hour. I called it a leak. It was not: the sample happened to span a
poll, where the network response and its parsing allocate and are then released.

One pair of measurements cannot distinguish a leak from a busy moment. The rule
worth keeping: a trend needs more than two points.

**Worth noting anyway.** ~70 MB for a menu bar app is not small. It is the cost
of SwiftUI plus WidgetKit rather than anything the code does wrong, but if the
figure ever matters, that is where to look first.

---

## 2026-08-31 · macOS widget verified as far as it can be without a user

The widget had been built but never observed. What could be checked without
placing it on a desktop:

- `pluginkit` lists `dev.example.StatusChecker.widget` — the extension is
  registered with the system, so the bundle and its Info.plist are well formed.
- The extension process runs, which means the system is rendering it: a widget
  that crashed on launch would not stay up.
- The system log holds no errors for the process or for `chronod` mentioning it.
- The app writes its snapshot to the shared path, verified earlier.

What cannot be checked from here is how it looks: placing a widget on the
desktop or in Notification Center is a user action. The desktop is currently
empty of widgets.

**Worth remembering.** "Builds and installs" is not "works". The chain
registered → launches → renders without error is the most that can be
established without someone adding it.

---

## 2026-08-31 · A false alarm about the widget, and what caused it

**What I concluded.** `lsof` on the running widget process showed only
`~/Library/Containers/dev.example.StatusChecker.widget/Data`. From that I decided
the widget was sandboxed away from its data and had been showing "no accounts"
all along, and started rewriting `SharedStore` to place a copy inside that
container.

**What is actually true.** The app group works. The container exists at
`~/Library/Group Containers/ABCDE12345.group.dev.example.StatusChecker`, the
snapshot is in it, current, with both accounts. A sandboxed extension opens the
group container only while reading, and `lsof` is an instant of time — the
absence of a path in it means nothing.

**What nearly happened.** The rewrite would have replaced a working app group
with a hack that writes into another process's private container. Caught only
because the file on disk did not match what I expected and I checked `HEAD`
before continuing.

**Two lessons.** An instantaneous view of open descriptors does not prove
absence. And when the code on disk surprises you, read it before editing it —
the surprise usually means the problem was already solved.

## The team identifier is not written down anywhere in the code

**Decision.** The entitlements say `$(TeamIdentifierPrefix)group.dev.example.StatusChecker`
and let Xcode expand it; `SharedStore.appGroup` asks the running binary which
groups it was granted, via `SecTaskCopyValueForEntitlement`, and takes the one
ending in `group.dev.example.StatusChecker`.

**Why.** macOS requires the team prefix in the group name and iOS does not, so
the identifier had been a hard-coded pair under `#if os(macOS)`. That put one
developer account's team ID into the source of a portable module: nobody else
could build the macOS target without editing a file in `Packages/Core`. The team
ID is not a secret — it is readable from the signature of any shipped app — but
it is not the module's business either.

**Cost.** The group name is now resolved at runtime rather than known at compile
time, so a mistake in the entitlements shows up as a fallback to the unprefixed
name instead of a build error. The fallback is what iOS uses, which is the right
answer on that platform and a wrong-but-harmless one on macOS: the container
simply would not be found. Verified after the change that the built app carries
`ABCDE12345.group.dev.example.StatusChecker` and that a restarted app still
writes the snapshot the widget reads.

## An account is one spoken sentence, not eight elements

**Decision.** `AccountRow` collapses into a single accessibility element whose
label is a sentence built by `Localization.spokenSummary(for:now:)`:

    Claude, name@example.com, Max 20x. Five-hour: 23% used, 3 hours 39 minutes
    left. Weekly: 45% used, 5 days 2 hours left. Data from 28 August 2026

The status item gets the same treatment, because its label reads "0:47" — spoken
back, "zero colon forty-seven", which is a time of day rather than a duration.

**Why.** Read element by element the row falls apart into fragments — "Claude",
"Max 20x", "5h", "23%", "3h 39m" — that arrive in the right order and say
nothing about how they relate. Worse, the row's meaning is carried by things a
screen reader cannot see at all: the length of a bar, the tick marking the
five-hour window, the ring sweep, and above all the colour, which is the only
place urgency is encoded. The number alone understates it.

Spoken time comes from `DateComponentsFormatter`, not the catalogue. The screen's
"3h 39m" reads as letters, so speech needs whole words, and whole words need
plural forms whose categories differ per language — four in Russian, six in
Arabic. The system knows all of them: asked for five days and two hours in
Arabic it returned `ساعتان`, the dual form, which a hand-written table of ten
languages would have got wrong.

**Cost.** Two catalogue keys, and a second phrasing of the same data to keep in
step with the first. `activeLocale` was extracted so the system formatters follow
the language chosen in settings rather than the system's — without it a Russian
sentence would end in English units.

**Verified, and not.** The composition is covered by tests in all ten languages,
including the placeholders being filled and a past reset producing no dangling
"left". The status item was read live out of the accessibility tree. The popover
was not: `NSPopover` does not surface as a window to System Events, so its tree
cannot be read from outside the process. What stands behind the row is the
ordinary SwiftUI mechanism and the tested sentence — not an observation.

## The tests were translated; their Cyrillic data was not

**Decision.** The comments and failure messages across all 22 test files are now
English, along with the docstrings of `tools/add_strings.py` and
`tools/make_icons.swift`. The Cyrillic that remains is data and stays:

- expected translations — `loc("Refresh") == "Обновить"`, `windowTitle("session")
  == "5ч"`, `remaining(13_140) == "3 ч 39 м"`;
- the fixture name `"Иван"`, which is there precisely because it is not ASCII;
- `"[А-Яа-я]"`, a pattern asserting that a Russian sentence came back Russian;
- `"Русский"` and `"العربية"` quoted inside English prose as examples.

**Why.** The project rule puts documentation and code comments in English. When
the sources were translated the tests were missed — the sweep looked at
`Sources/` and stopped there. `CoreHasNoHumanStringsTests` even carried a comment
asserting that Russian comments are addressed to the developer and not subject to
translation, which had been true when it was written and was not any more.

**Cost.** Almost none in behaviour — 173 tests pass unchanged. The risk this
entry guards against is the next sweep: a scan for Cyrillic now returns eleven
lines, every one of them load-bearing. Translating them would leave the tests
passing while checking nothing.

## `make build` used to succeed when the build failed

**Decision.** Every recipe that pipes `xcodebuild` now starts with
`set -o pipefail`, and the pipe filters for `error:` rather than taking the last
few lines.

**Why.** The recipes ended in `| tail -5`, so the shell returned `tail`'s exit
status and `make build` reported success no matter what `xcodebuild` did. The
tail also cut away the `error:` lines, leaving only "The following build
commands failed" with no reason.

`.SHELLFLAGS := -o pipefail -c` is the tidy way to say this, and it does not
work: it arrived in GNU Make 3.82 and macOS ships 3.81, which ignores it in
silence. That was found by deliberately breaking a source file and watching
`make build` still return 0 — had the fix been trusted rather than tested, the
Makefile would now carry a line that reads like a guarantee and does nothing.

**How it surfaced.** The previous entry's change — reading the app group from
the entitlements — used `SecTaskCopyValueForEntitlement`, which does not exist
on iOS. `Packages/Core` is shared, but only the macOS build and the running app
were checked, so the break shipped. The rule it costs: **an edit inside
`Packages/Core` is verified on both platforms before it is committed**, because
the module's whole purpose is that it belongs to neither.

**Cost.** Build output is now filtered by pattern instead of truncated, so an
unmatched line is invisible. That is the trade for seeing the errors at all.

## The browser sign-in sent port zero

**Decision.** `LoginController` waits for the listener to reach `.ready` before
building the return address, and the address itself is built by
`OAuthEndpoints.localRedirect(port:)`, which answers `nil` for port zero.

**Why.** The browser came back with "Redirect URI http://localhost:0/callback is
not supported by client", and zero is not a port the service could ever accept.

The wait was written as

    while listener.port == nil { … }

which reads correctly and is wrong. `NWListener.port` does not answer `nil`
before the socket is bound — it answers the endpoint the listener was *asked*
for, and the request was `.any`, which is zero. So the loop finished on its
first look, with a port bound to nothing, and that zero travelled through the
authorize URL to the service. Confirmed directly: a listener reports
`port = 0` both before `start()` and immediately after it.

**Why the check moved into `Packages/Core`.** The defect was a value that must
never be zero, sitting in `App/`, where no test could see it. As a function in
`ClaudeProvider` it is three lines and three tests, and the next caller cannot
repeat the mistake.

**Cost.** Binding is now awaited rather than spun on the run loop, so `start()`
hands off to a `Task` and the browser opens one turn later — which is also why
the run loop is no longer blocked while the socket comes up. A listener that
fails to bind still falls back to pasting the code by hand.

**Not verified.** That the corrected flow completes end to end. The remaining
step needs a real sign-in in a browser, which only the account's owner can do.

---

## 2026-08-31 · Self-review of the ⌘⇥ and app group work

Eight findings, six fixed, two answered.

**The wait for the settings window was a single 200 ms shot.** If the window was
not up in time the code returned the app to `.accessory` while the window was
still on its way: it then arrived outside ⌘⇥ — the very thing the file exists to
prevent — unfocused, and with nothing watching for its close. It now looks every
50 ms for about a second and a half. This also covers a menu item that was found
but did nothing: `performActionForItem(at:)` is silent for a disabled item, so
success cannot be read from the call, only from the window appearing.

**The app group produced nothing without a signing identity.** With no
`Signing.local.xcconfig`, `$(TeamIdentifierPrefix)` expands to the empty string,
macOS is handed a group name with no team prefix and grants no container — and
`write` and `read` both returned quietly, leaving an empty widget and no trace
anywhere. The failure is now logged, as is a failed write.

**The widget was versioned `1.0` against the app's `0.1`,** and carried no
hardened runtime. Notarisation rejects both: an embedded extension must match
the containing app's version, and every nested executable must be hardened.
Both now come from the target.

**`make run-ios` broke on a machine without an iPhone 16 or 17 simulator:** the
device id came out empty and `simctl install` failed with a confusing message.
It falls back to any iPhone, says so plainly when there is none, and waits for
the boot to finish instead of racing it.

**Answered, not fixed.** The settings window cannot be minimised — SwiftUI
disables the button on a `Settings` scene, verified through the accessibility
tree — so the reported "minimise, then the menu item does nothing" cannot
happen. `present()` deminiaturises anyway: one guarded line, and the window is
not the only thing that could ever be handed to it. Reordering `existing()` to
run its loose fallback only after the menu item was performed was declined: that
fallback is what reopens a closed-but-kept window, which works today.

## A percentage is typography, not arithmetic

**Decision.** All six places that rendered a percentage by interpolation now call
`Localization.percent(_:)`, which formats through `IntegerFormatStyle.Percent`
in the chosen language's locale. The percent column widened from 34 pt to 38 pt.

**Why.** `"\(Int(value))%"` is only right in English. Russian, French and
Spanish put a non-breaking space before the sign, and Arabic wraps it in
directional marks so it stays put when the line runs right to left — four of the
ten languages the app ships. The app also disagreed with itself: a row said
"80%" while the notification thresholds beside it said "80 %".

The width followed from the same measurement. Rendered in the row's font,
`100 %` is 34.4 pt against a 34 pt column: it would have been clipped at exactly
the reading that matters most, an account with nothing left. The extra 4 pt come
out of the bar, which is flexible.

**Cost.** One formatting call per row per redraw instead of string
interpolation, which is nothing at this size. The spoken form keeps `%%` inside
its catalogue sentence rather than sharing this function: there the sign is read
as a word, and each translation already decides its own spacing.

**Where it does not apply.** The ring shows a bare number with no sign, and the
menu bar's compact timer is a duration rather than a percentage.

## The sign-in failure that could not be read

**Decision.** Three things, after the first browser sign-in reached the token
exchange and failed:

1. `state` is sent in the exchange body, not only in the authorize query.
2. `ProviderFailure.diagnostic` is written to the log when a sign-in fails.
3. The window for completing a sign-in went from 2 minutes to 5, and the HTTP
   timeout from 15 seconds to 30.

**Why.** The port fix worked — the browser came back to `localhost:56017` with a
code, and the app consumed it. Then the interface said "Sign-in required" and
that was all anyone could know: `.needsLogin` is thrown from three different
places — the exchange returning a non-200, an exchange with no refresh token,
and a failed profile read — and all three arrive as one sentence.

The diagnostic that distinguishes them was being built and discarded. The model
had said all along that it is written for the log; nothing was writing it. So
the second change is really the first: without it the next attempt is another
guess.

The `state` difference came from reading what Claude Code actually posts:
`grant_type, code, redirect_uri, client_id, code_verifier, state`. This app was
sending everything but the last. Whether the service requires it is not
established — but a difference from a request known to work is not a difference
worth keeping while chasing a failure.

Five minutes rather than two because signing in to a *second* subscription means
a password, a verification code and a consent screen; the old limit could expire
while the browser was still on the first of them.

**Cost.** The exchange signature grew a parameter, which reached four tests. The
logged diagnostic is deliberately coarse — the HTTP status, never the body,
which can carry the code or the verifier.

**Not established.** Which of the three failures actually occurred. The code was
single-use and is spent; the next attempt will say so in the log.

---

## 2026-08-31 · The project is named Softcap

**Decision.** StatusChecker becomes **Softcap**. The domain `softcap.app` is
bought and its DNS moved to DigitalOcean.

**Why.** A soft cap is exactly what a Claude or Codex subscription limit is: not
a wall, a rolling window that releases on its own. The audience is developers who
run into those windows, and for them this is the term for the thing rather than a
metaphor. The name also survives new providers, which a name built around Claude
or Codex would not.

**How it was chosen.** Availability was measured, not guessed: candidates went
through RDAP in `.app`, `.dev` and `.com`, where `404` means unregistered. Nearly
every single-word English candidate was gone — `headroom`, `leeway`, `burnrate`,
`cooldown`, `quota`, `allowance`, `waterline`, `loadline`, `freeboard`,
`plimsoll`, `ullage`. What survived was `softcap`, `ceiling` and a handful of
two-word compounds. `untilreset` was free in all three zones and on GitHub, but
it is a phrase rather than a name and narrows the product to one of its two
numbers.

**Cost.** `softcap.com` and `github.com/softcap` were already taken, so the
GitHub home has to be a different handle. The phrase is also well worn by crypto
fundraising ("soft cap" / "hard cap"), so the name starts at a disadvantage in
search.

## The sign-in was blocked by Cloudflare, not refused by OAuth

**Decision.** `OAuthEndpoints.userAgent` and `OAuthEndpoints.jsonHeaders` define
the client's identity once, and both calls to the token endpoint — the code
exchange and the refresh — now carry it.

**Why.** The previous entry logged a sign-in that failed with nothing to say
why. Rather than wait for another attempt, the endpoint was asked directly with
a deliberately invalid code, which is a safe question: a wrong code earns an
OAuth error, and the *shape* of that error says whether the request was
understood.

    no User-Agent    → HTTP 403, "error code: 1010"
    User-Agent set   → HTTP 400, {"error": "invalid_grant", …}

`1010` is Cloudflare rejecting the caller's fingerprint, not the service
answering. The header was on the profile and usage reads and absent from
exchange and refresh — the two calls that carry the point of the app: signing an
account in, and keeping an inactive one alive. The refresh failure had never
been seen because no account has yet gone inactive; it would have appeared as
the second subscription silently going stale.

The same probe settled the previous entry's open question. Without `state` the
endpoint answers `"Invalid request format"` — so sending it was necessary, not
merely a difference tidied away. Both were real defects, and either alone
produced the same "Sign-in required".

**Cost.** The app presents itself as `claude-cli/2.0.0 (external, cli)`, which
is the client the sign-in was started under and whose scopes it holds — but a
string the service could stop accepting. A test asserts the exact spelling, so a
change is a failing test rather than a 403 read as a lost password.

**Verified.** Three tests, checked by removing the header and watching them
fail. Not verified: a complete sign-in, which needs the account's owner.

## Opening the window was what stopped the accounts loading

**Decision.** Polling is scheduled by `PollScheduler` in `Monitoring`, which
separates the schedule from the work: re-arming the interval cancels the timer
and never the run already under way.

**Why.** Two accounts showed "Network unavailable" while a third loaded fine, and
the network was in order — the endpoints answered when asked directly. The
diagnostic, once it carried the real error instead of a fixed phrase, said
`URLError -999`: cancelled. The requests were not failing, they were being
stopped.

By whom follows from two lines that were fifty apart:

    var isPopoverOpen = false { didSet { restartTimer() } }
    private func restartTimer() { timer?.cancel(); … }

The poll ran inside the timer's task, so every open and close of the window
cancelled a poll in progress. Accounts are polled one after another, which is
why the first finished and the rest died — and why the window, freshly opened,
showed exactly the accounts it had just prevented from loading.

It stayed hidden while there was one account: a single poll is short and the
collision is unlikely. Three accounts made it long enough to lose every time.

**Cost.** An unstructured task inside the loop breaks the cancellation chain,
which also means `stop()` no longer ends a poll already running — it ends the
schedule, and the last run finishes. For a poll of three HTTP requests that is
the behaviour worth having.

**Verified.** Three tests, and the important one was checked by removing the
separation and watching it fail — a run that started did not finish. The defect
lived in `App/`, where nothing could test it; the invariant now lives in `Core`.

## Codex names its windows by length, not by position

**Decision.** `RolloutParser` decides whether a reading is the five-hour or the
weekly window from its `window_minutes`, not from whether it arrived in
`primary` or `secondary`.

**Why.** The parser had been written against the shape in the design document —
`primary` the five-hour window, `secondary` the weekly one — and that shape is
real but not the only one. Codex also writes events like

    "primary": {"used_percent": 38.0, "window_minutes": 10080, …}, "secondary": null

where the weekly window arrives first and alone. Read by position those figures
were labelled `session`, so a weekly percentage was displayed as a five-hour
one: a wrong number under a right-looking name, which is worse than no number.

The scale only became visible when a month of session files was imported at
once: 1,917 of the 1,921 Codex readings on this machine are weekly, and every
one of them had been filed as five-hour. The design document said all along that
`window_minutes` 300 is the short window and 10080 the weekly one; the code read
the slot instead.

**Cost.** A threshold has to be picked for lengths neither 300 nor 10080. A day
is the split — anything shorter belongs with the short window, which is the only
other name the interface has.

**Verified.** Three tests, checked by restoring the old mapping and watching all
three fail. Then against the real files: with the fix, 1,917 readings move from
`session` to `weekly`, which is the correction rather than a coincidence.

## Statistics: one chart, weekly windows, cool colours

**Decision.** A `Statistics` section drawing one line per account on one plot,
over the last week or month. Three choices worth stating:

**The weekly window, not the five-hour one.** Over seven days the short window
resets thirty-three times and over a month a hundred and forty-four — a comb,
not a chart. The weekly window resets once a week, so each tooth is one week's
allowance: its height is what was spent, and a flat top is an account that ran
out.

**Colour means identity here, and load everywhere else.** The limits window
already speaks in colour — green through red is the load scale. Reusing those
hues to tell accounts apart would put two meanings on one channel, and a blue
line at 90 % would look calmer than a red one at 20. So identity is cool
(blue, violet, teal, mauve, indigo) and load stays warm, and neither borrows
from the other. Colours are assigned by position in a sorted list, so a line
does not change colour between redraws.

**A gap in recording is a gap in the line.** The app is not always running.
Drawing straight across the hours it slept would claim a steady figure nobody
measured, so a quiet spell longer than two hours splits the series and the
screen says why.

**History had to be invented, and half of it already existed.** Nothing was kept
before: the app knew only its latest reading. Recording is stingy — a reading is
kept when it moves by a point, at most every five minutes, and unchanged once
every half hour so that a flat line stays distinguishable from a gap. Codex,
though, has written its own readings into session files for weeks, and importing
them gives that line a month of past on first launch. Claude has no equivalent —
its API answers for the present only — so the two lines start out very
differently, and the screen does not pretend otherwise.

**Cost.** A second file in the app group, capped at 35 days: 1,927 readings came
to 209 KB. `UsageSample` moved into `ProviderKit` so a provider could produce
samples without depending on `Monitoring`, which would have inverted the
direction of the modules.

## Every push to main publishes an installable build

**Decision.** A GitHub Actions workflow builds `StatusChecker.app` on each push
to `main`, packs it into a disk image, and publishes it as a release. Three
choices worth stating:

**The app is signed after the build, not by Xcode.** The entitlements ask for an
app group, and under `CODE_SIGN_STYLE = Manual` Xcode refuses to sign that
without a provisioning profile — which a runner with no Apple account cannot
obtain. So the build runs with signing off and `tools/sign_app.sh` signs the
bundle afterwards, expanding `$(TeamIdentifierPrefix)` by hand. The alternative
was to drop the app-group entitlement to make the build pass, which would have
shipped an app whose widget is permanently blank: the group is precisely what
lets the widget read what the app fetched.

**The README link is fixed, so it cannot go stale.** GitHub keeps
`/releases/latest/download/<name>` pointing at the newest release, so the image
is uploaded twice — once under its version for the archive, once under a fixed
name for that URL. The workflow rewrites only the version and date beside the
link, inside a marked block, and commits nothing when they are unchanged. A
link that is regenerated on every build is a link that breaks on the build that
fails halfway.

**Signing is optional, and the release notes say which kind it was.** Without a
Developer ID the build is signed ad-hoc and macOS refuses it on first launch, so
the notes carry the `xattr` line for that case. Adding four secrets turns on a
real signature and notarisation with no other change. Refusing to publish
unsigned builds would have meant no downloads at all until a paid account
exists; publishing them silently would have meant a download that appears
broken.

**Cost.** The disk image is built with `hdiutil` alone rather than `create-dmg`,
so it has no custom window layout: that layout is set through AppleScript, which
needs a Finder a headless runner does not have. Version numbers are
`MARKETING_VERSION` plus the run number, so they climb with every push and carry
no meaning beyond order.

## Two readings of the chart that only the screen could settle

**Decision.** Two changes made after looking at the drawn chart rather than at
the code:

**Legend names lose a shared domain.** Three accounts on one mail host read as
`sam.k@example.com` and `sam.kim@example.com`, and in a legend's width
both truncated to `sam.k…example.com` — the middle, which is exactly what
tells them apart. The shared domain is dropped, leaving `sam.k` and
`sam.kim`. Only a domain every *address* shares: two hosts in the list
would make the domain the distinguishing part. A name that is not an address at
all — Codex calls its account after the person — is left alone and does not stop
the addresses being shortened, which is the real list on this machine.

**A run of one reading draws a dot.** A newly added account has exactly one
sample, and a line through one point has zero length: nothing on screen. Three
accounts added today were invisible, which reads as missing rather than new.

**Why it took looking.** Both were invisible in the code and obvious in the
picture. The first screenshot showed two legend entries that could not be told
apart; the second showed an empty plot for accounts that had readings.

**Cost.** The shortening is a guess about what a name means — it treats a string
with `@` as an address. A display name that happens to contain one would lose
its tail in the legend and nowhere else.

## One rule for what a reading is worth keeping

**Decision.** Imported readings are thinned by the same rule the app records
under — `UsageHistory.thinned(_:)` — before they are merged.

**Why.** Live recording keeps a reading when it moves by a point, at most every
five minutes. The Codex import kept everything, and Codex logs a reading on every
turn: 822 in a single day, 1,927 in a month. One history held two densities, and
the sentence describing how much is kept was true of only half the file.

Thinning is deterministic and looks only at the incoming run, not at what is
already stored, so importing the same files on every launch yields the same
readings and `merge` drops them as duplicates.

**Measured.** 1,927 readings became 82, and the file went from 209 KB to 8 KB.
The shape survived: 18 Aug still reads 0–27 %, 19 Aug 27–37 %, 22 Aug 38–39 %.

**Cost.** A peak reached and left within five minutes can be missed, and the
drawn maximum can sit a point or so below the true one. On a chart of a weekly
allowance that is not a difference anybody acts on.

**What it exposed.** The screen said a break in a line means the app was not
running. For Codex that is wrong — its readings come from session files written
whether or not this app exists, so a gap there means Codex was not used. The
wording now says no readings were taken, which is true of both.

## Measuring first, and then not optimising

**Decision.** `UsageHistory.record` still sorts the whole array on every call and
`UsageHistoryStore` still compares the whole history to decide whether to write.
Neither was changed.

**Why.** Both looked wasteful: a full sort of a month of readings once a minute,
and an equality check over fourteen thousand elements. Benchmarked at that size,
a hundred polls that record nothing cost 125 ms — 1.25 ms per poll, against a
poll interval of sixty seconds. The comparison did not register at all.

Rewriting either would have added a state to keep in step for no gain a person
could perceive. The measurement is the entry: without it the change looks
obviously right, which is how correct code gets replaced with clever code.

## The harness worktree was ignored by a file that does not travel

**Decision.** `.claude/` is listed in the committed `.gitignore`, not only in
`.git/info/exclude`.

It was already ignored, so nothing was wrong on this machine. But
`.git/info/exclude` belongs to one clone: it is not committed, it does not
survive a fresh clone, and nothing about the repository records that the rule
ever existed. Behind it sat 751 MB across 10,367 files, including a second full
checkout of this repository — one `git add -A` from being committed, on any
clone where that local file was missing.

That is the same failure the `.build` rule above documents: 287 MB reached the
repository because the rule was not there from the start. Having it happen twice
for the same reason, on a repository about to be made public, is what moved the
rule to the file that travels with it.

**Cost.** None to the build. The local `.git/info/exclude` still lists the same
paths, so the two now overlap — harmless, and the durable one is the one in the
tree.

## Personal data is kept out by a test, not by care

**Decision.** `NoPersonalDataInTheRepository` scans every committed text file for
mail addresses outside the domains reserved for examples (RFC 2606), account
identifiers of the shape this app deals in, anything shaped like a token or a
JWT, and absolute paths under `/Users`. The addresses already in the repository
used invented names at four ordinary domains — three in the mock-ups, one in a
test — and moved to `example.com` and `example.org`. The names were invented; the
domains were not, and one of them is a very well-known service.

The entry deliberately does not quote the old spellings. The test scans this file
too, and a rule with an exception for the document describing it is a rule with
an exception.

**Why.** Writing the legend code, the account list of the machine it was written
on went into a test, a doc comment and a decision entry — three real mail
addresses, committed. A person reading the diff caught it, and only because this
repository has never been pushed was that in time.

Care is not a mechanism. The project already guards an architectural rule with a
test that reads the sources; the same shape works here, and it fails on a diff
rather than on a reader noticing.

**Cost.** A false positive is possible — a documented address at a real domain,
a support contact — and would have to be added to the allowed list. Nothing of
the sort exists here.

**Note.** The scan skips `.claude`, where the agent harness keeps git worktrees:
whole checkouts of this repository at other commits. Walking into one reports
its files as if they were these, which reads as a leak already fixed here and
merely still present on another branch — a false alarm that cost a full round of
diagnosis to see through.

**Still open.** The addresses remain in the history, in the commit that
introduced them. The repository has never been pushed, so rewriting is possible;
whether to is the owner's call.

## The account's name is asked for once, not every minute

**Decision.** `ClaudeIdentityCache` remembers an account's display name and plan
label for six hours. The provider asks the profile endpoint only when the cache
has nothing.

**Why.** Two things, found while checking a claim on the landing page rather than
in the code. The page said one HTTP request per Claude account per poll; there
were two, because the profile was fetched alongside the usage every time — for an
address and a plan name that change about never. Once a minute with the window
open, times three accounts.

The second reason matters more. A failed profile read dropped the row's name to
`claude/<uuid>` while the usage figures beside it stayed correct — the ugly rows
seen earlier were partly this. On screen that reads as a different account rather
than as the same one with a hiccup. A remembered name survives the hiccup.

**Six hours, not forever.** A plan can be upgraded and an address changed. Long
enough that no poll pays for it, short enough that a change shows up the same day.

**Where it lives.** In `AppModel`, not in the provider: the provider is a value
rebuilt before every poll, and a cache rebuilt with it would never hit. Forgetting
an account forgets its name too.

**Cost.** State that outlives a poll, which is what was being avoided by not
having it. Eight tests, including one that counts the requests a repeated poll
actually makes: one profile read, three usage reads.

## The landing page, and how it is deployed

**Decision.** `site/` holds a single self-contained HTML page served at
<https://softcap.app/>. `site/deploy.sh` ships it to the host that already serves
the owner's other sites.

**How the host works.** Everything on it runs in Docker behind `kamal-proxy`,
which terminates TLS and routes by the Host header. A static site there is a
stock `caddy:2-alpine` with the files bind-mounted, joined to the `kamal`
network so the proxy can reach it by container name. The landing follows that
pattern exactly rather than inventing a second one: `/opt/softcap-site` with a
`Caddyfile`, a `dist/`, and a compose file. Registering the route is one
`kamal-proxy deploy`, which also obtains the certificate.

**One file, no build step.** The page is HTML with its styles inline and one SVG
icon beside it. No framework, no bundler, no external request — not even a font.
A page explaining a menu bar utility does not need a toolchain, and a deploy
that is `rsync` plus `docker compose up` cannot rot between uses.

**What the page says.** It is written for the people who would install this, so
it leads with the two engineering decisions rather than with features: that
measuring the Codex quota must not spend it, and that the monitor must not sign
your CLI out. The interface is recreated in CSS rather than screenshotted —
sharp at any density, no personal data in it, and it cannot fall out of date
quietly the way an image does.

There is no download button. The app is not released, and a button that does
nothing is worse on a page like this than the plain sentence that it is in
development.

**Cost.** A recreated interface is a second copy of the design that will drift
from the real one unless it is updated by hand. The alternative — a screenshot —
drifts too, and silently.

**A claim on the page corrected the code.** Writing "one HTTP request per account
per poll" and then checking it found two, and the second one was avoidable. That
entry is above.

**Verified, and not.** The page was rendered and read at 485, 753 and 1425 px
wide, with a script reporting any element wider than the viewport: none. Below
485 px it could not be checked — headless Chrome on macOS will not make a window
narrower than that. The narrow-screen rule is therefore reasoned rather than
seen: at 390 px the window mock plus two sets of padding comes to 426 px against
354 px of content, so it would scroll sideways without the rule.

## `caddy reload` said yes and did nothing

**Decision.** `site/deploy.sh` restarts the container rather than reloading it.

**Why.** The Caddyfile is bind-mounted, so shipping a new one changes the file
but not the running server: Caddy keeps its configuration in memory, and
`docker compose up -d` will not restart a container whose spec is unchanged. The
graceful answer is `caddy reload`, which printed `adapted config to JSON` and
exited zero — and left the old rules running. Asking the admin API for the live
configuration showed `try_files` still in it, minutes after the reload.

A restart applied the change immediately. The container is a static file server
that starts in well under a second, and the `kamal-proxy deploy` that follows
health-checks it before routing, so the blip is covered.

**How it was noticed.** Not by the deploy, which reported success both times. By
asking the site for a path that does not exist: it answered `200` with the
landing page. That is a soft 404 — a search engine files it as a page that
exists, and a reader who mistypes a link is told nothing. The SPA fallback that
caused it had been copied from the neighbouring site, which is a single-page
application; this is one page and wants a plain `file_server`.

**Cost.** A deploy now interrupts the site for a moment instead of swapping
configuration under it. For a page with no sessions and no state, that is not a
cost worth engineering around.

## The link preview is rendered, not drawn

**Decision.** `site/og.png` is produced by pointing headless Chrome at
`site/og-template.html`. The template is HTML using the same tokens as the page.

**Why.** A shared link showed a bare URL, which for a page whose whole audience
arrives through other people's messages is most of the first impression. The
usual answer is an image made in a design tool, which then lives as a binary
nobody can edit and drifts from the copy it illustrates. A template re-renders in
a second when the headline changes, and it cannot use a colour the page does not.

**Cost.** A 130 KB PNG in the repository that is generated, not authored — so it
has to be regenerated deliberately after a copy change, and nothing enforces
that. The command is in the file next to it.

**Also added.** `canonical`, `theme-color`, a Twitter card, `robots.txt` and a
sitemap. And a correction: the widget cell claimed "every size" on both
platforms. macOS has all four; iPhone has three plus two lock-screen families,
which is a better thing to say than a vaguer one that happens to be true.

## The captions on the landing failed contrast

**Decision.** `--fg-3`, the muted grey the landing uses for section labels,
captions, the footer and the mock's secondary text, went from `#6b6b78` to
`#828291`.

**Why.** Measured rather than eyeballed: the old grey was **3.67:1** against the
page background, below the 4.5:1 that WCAG asks of normal text. It was carrying
the eyebrow labels, the monospace note under the headline, the term column of the
facts list and the footer — small text, which is where the ratio matters most.

The replacement measures 5.09:1 on the page, 4.57:1 on the window mock's card and
4.81:1 on the chart panel: above the line on all three surfaces it appears on.
The other colours were checked at the same time and all pass — the severity
scale, which came from the app, sits between 4.86 and 9.87.

**Why it is here at all.** The app got a spoken description for every account
because a screen reader could not see its bars. Letting the page that explains
that decision be unreadable to a reader with low vision would be the same mistake
in a different medium.

**Cost.** The muted greys are a shade lighter than the design started with. The
hierarchy still reads — the gap between body text at 6.92:1 and captions at
5.09:1 is what carries it, not the absolute darkness.

## The landing now shows the menu bar, not just the window

**Decision.** The hero mock gained the macOS menu bar strip above it, with the
status item highlighted and showing `0:41`, and the window hanging below it on a
pointer.

**Why.** The page said "Softcap sits in the menu bar" and then showed a floating
window, which is the thing you see least. The strip is what the app actually is
for most of the day: an icon and a countdown at the top of the screen. Showing it
says that faster than the sentence does.

**One measured number.** `--anchor` is how far the status item's centre sits from
the right edge — 160 px, read out of the browser rather than guessed. The first
attempt guessed 212 and the pointer missed the item by 53 px, which a screenshot
made obvious and arithmetic had not.

The pointer is placed from that number; the window is not. A 322 px popover
centred under an item 160 px from the edge would hang off the side — so it slides
inwards and leaves the pointer behind on the item. That is not a compromise, it
is what macOS does when a status item sits near the edge of the screen.

**Below 760 px** the window centres and the pointer is hidden: there is no room to
hang it off a point, and a pointer aiming at nothing is worse than none. Checked
at 485, 685, 885 and 1385 px — nothing overflows at any of them.

**Cost.** More recreated interface to keep in step with the real app. The same
trade as the window itself, and the same reason: an image would drift too, and
silently.

---

## 2026-08-31 · The old identifier's last traces

**Decision.** All four bundle identifiers now live under `app.softcap`:
`app.softcap.Softcap` (macOS app), `app.softcap.Softcap.widget` (macOS
widget), `app.softcap.Softcap.ios` (iOS app) and `app.softcap.Softcap.ios.widget`
(iOS widget). The two widget kinds changed too, to
`app.softcap.Softcap.limits` (macOS) and `app.softcap.Softcap.ios.limits`
(iOS) — which is why a desktop widget placed under the old kind is left
orphaned. The app group moved the same way, to `group.app.softcap` —
spelled with the team prefix on macOS (`$(TeamIdentifierPrefix)group.app.softcap`,
resolving to `ABCDE12345.group.app.softcap`) and bare on iOS
(`group.app.softcap`). `CredentialStore.ownService` did not move: it is still
the literal string `"StatusChecker-accounts"`.

Three things the old identifier left on disk got three different endings. The
orphaned `~/Library/Application Support/dev.example.StatusChecker` directory —
orphaned since the snapshot moved into the app group, see the entry from the
previous evening on the macOS widget's app group — was quarantined. Settings,
the launch-at-login registration and the placed desktop widget were not
carried forward at all. `~/Library/Preferences/dev.example.StatusChecker.plist`
and the old `~/Library/Group Containers/…group.dev.example.StatusChecker/`
were both left exactly where they are.

**Why the Keychain service didn't move.** Keychain access is granted to a code
signature, not to a bundle identifier, so the rename changes nothing about who
is allowed to read an existing item — but changing the service string would
have moved every stored account out from under itself. Those accounts are also
the one thing on this list that does not come back on its own: settings return
to their defaults, launch-at-login can be flipped back on, a widget can be
re-added, but a lost account means signing in again through OAuth for every
subscription it had accumulated. `ownService` stayed `"StatusChecker-accounts"`
on purpose, not by oversight.

**Why settings and the widget were dropped instead of carried over.** There is
exactly one installation of this app, on one machine, belonging to the person
doing the rename. Code that reads an old preferences key and writes it back
under the new identifier would run exactly once, for exactly one person, and
then stay in the tree as something the next reader has to understand and the
next change has to keep working. Re-doing three things by hand once is cheaper
than carrying that code forever.

**Why the preferences file and the old group container were left alone.** The
plist is not dead: the app in everyday use right now is the old-named build
from the other checkout, and that file holds its live settings. Quarantining
it before this branch merges would reset the settings out from under whoever
is actually running it — it moves at merge time, not before. The old group
container is not dead either: beside a regenerable `snapshot.json` it holds
`history.json`, an accumulated record kept by a history feature that is not
part of this branch — unmerged work in the other checkout, still writing to
the old group name. Merging this rename points that feature at the new
container and strands what `history.json` has gathered so far, so the old
container is left alone on purpose: whoever merges the history feature has
to carry `history.json` across by hand, or accept starting the record over.

**Cost.** Launch at login has to be switched off and back on, and the widget
has to be placed on the desktop again, once this branch lands. So is
quarantining `~/Library/Preferences/dev.example.StatusChecker.plist`, left in
place until then for the reason above.


## The landing says what it does not do, in headers

**Decision.** The site sends `Content-Security-Policy`, `X-Content-Type-Options`,
`Referrer-Policy`, `Permissions-Policy` and `X-Frame-Options`, and suppresses the
`Server` header. It does **not** send HSTS.

**Why.** The page runs no JavaScript, loads no font, embeds no frame and posts no
form, so the policy can name exactly that rather than leaving room the page never
uses:

    default-src 'none'; img-src 'self'; style-src 'unsafe-inline';
    base-uri 'none'; form-action 'none'; frame-ancestors 'none'

`unsafe-inline` for styles is unavoidable while the CSS lives inside the document,
which is the point of shipping one file. It is also close to harmless here:
`script-src` is denied outright, so there is nothing for an injected style to
cooperate with.

**Why HSTS is absent.** It is the one header a browser remembers, and it would
commit this domain to HTTPS for everyone who has already visited. That is a
promise to make deliberately, not as a side effect of hardening a landing page —
and it would reach any future service on the apex, not only this one. The
HTTP→HTTPS redirect already covers the ordinary case. Worth adding on purpose,
by the domain's owner.

**Verified.** Headers read back off the live URL, and the page rendered with no
policy violation in the console. Also checked while writing this: the app's only
network destinations are `api.anthropic.com`, `claude.com` and
`platform.claude.com`. A grep turned up `api.openai.com` and it was a false
alarm — a JWT claim key read out of a local file, not a request. So the page's
claim that Codex costs nothing over the network holds.

## The headline breaks where it is written to break

**Decision.** The second half of the headline is a block element, and the
headline's `max-width` is 22ch rather than 16ch.

**Why.** The page carries no font of its own — it uses the system stack, which is
SF Pro on a Mac and something wider almost everywhere else. Rendered in Arial the
headline became three lines, splitting `on one / screen.` and losing the pairing
the two halves are written as. Verdana and Georgia are wider still.

`ch` is measured from the digit zero, which is narrow, so a container sized in
`ch` is generous in SF and tight in nearly everything else — the unit promises
portability and does not deliver it for display text.

Making the second phrase its own block fixes half of it; widening the container
until the first phrase fits the widest common fallback fixes the rest. Checked at
22ch in SF, Arial, Verdana and Georgia: two lines in all four, and the Mac
rendering is unchanged because the phrase never came near the old limit.

`text-wrap: balance` was tried first and removed. It redistributes lines to even
them out, which is the opposite of a break placed on purpose.

**Cost.** A wider box than the text needs on a Mac. It is invisible: the line
ends where the words end, not where the box does.

**Measured while there.** The page is 23.8 KB and 8.1 KB over the wire — `encode
zstd gzip` in the Caddyfile is doing its job.

## The access log said what to fix next

**Decision.** `site/favicon.ico` is served, built by `site/make-favicon.sh` from
the same `icon.svg` the page uses.

**Why.** The page declares an SVG icon, which every current browser prefers — and
several still ask for `/favicon.ico` anyway. The log showed four such requests
answered with a 404. That is the whole justification: not a guess about what
browsers do, a count of what they asked for.

The same log settled a second question. Scanners had probed `/.env`,
`/.git/config`, `/.env.local` and `/config.json` — and been answered **200**,
because at that moment the SPA fallback was still returning the landing page for
every unknown path. Nothing sensitive was ever in that directory, which holds
five files and no secrets, so what they collected was HTML. But the soft-404 had
a consequence beyond search engines that had not occurred to me: to a scanner,
`200` on `/.env` reads as a hit. All four now answer 404, and the fix was already
in place before the question was asked.

**The small-size rule came from the app.** Below 40 px the icon drops its inner
ring and thickens the outer one, because two concentric strokes a few pixels
apart merge into a smudge. The app's icon generator has said so since it was
written; the first favicon ignored it and the 16 px version was an unreadable
blob. It is the same mark and it keeps the same rule.

**A `sed` that matched too much.** The first render stripped `width="64"
height="64"` to size the SVG by CSS — and the file's background rectangle carries
exactly those attributes on its own line, so it lost its size and the dark plate
vanished. The icon came out as a green arc on white. The script now leaves the
file alone and sizes it in CSS, which was the correct way from the start.

## The preview shows the menu bar too

**Decision.** `site/og-template.html` gained the menu bar strip above the window,
matching the hero on the page.

**Why.** A preview gets one glance. Showing the window alone says "an app";
showing the strip with the item on it says *which kind* of app — which is the one
thing worth landing before anybody clicks. The page had been changed to lead with
it; the preview had not.

**Cost.** The image is 133 KB and generated, so a copy change means running the
render again. Both that command and the favicon's are in the README, next to the
deploy.

**Removed while there.** A pointer triangle between the strip and the window,
which rendered invisibly — its colour was the window's border, which reads on the
page's lighter stage and disappears on the preview's dark ground. Markup that
draws nothing is worse than none, so it went rather than being recoloured: on the
preview the strip sits directly on the window and reads as attached without it.

## The landing's copy of the interface is now checked, not trusted

**Decision.** `TheLandingUsesTheAppsWords` reads `site/index.html` and the English
catalogue and holds them together in three ways: every label the mock shows must
be a key the app still has; every label listed in the test must still be on the
page; and the page must not carry a former name of the app.

**Why.** The mock was introduced with its cost written down — "a second copy of
the design that will drift from the real one unless it is updated by hand" — and
then nothing was done about it. Rename a key in the app and the landing keeps
showing the old word, correctly rendered and quietly wrong. The rename to Softcap
had already passed through this repository between then and now.

**What it cannot do.** Check the layout. It compares words, so a mock that has
drifted in spacing, order or colour still passes. That part needs a person to
look, and the test says so rather than implying otherwise.

**Two mistakes while writing it, both found by trying to break it.**

The first version searched the whole file for each label. Renaming the mock's
`Refresh` button changed nothing, because the word also appears in the prose
below as "Refreshing it can rotate…" — a test that passes for a reason unrelated
to what it claims. The check now looks only inside the mock's own markup.

Narrowing it introduced the second: the closing line was found by searching for
`win-foot` from the top of the file, and that names a rule in the stylesheet
several hundred lines earlier — so the end landed before the start. It is
searched for after the opening line now.

**Cost.** A list in the test that has to be updated when the mock deliberately
changes. That is the intended friction: changing what the page claims should
require saying so.

## The widget is registered from a worktree, not from the checkout

**Observation, not a change.** `pluginkit` lists the widget extension at

    .claude/worktrees/rename-softcap/build/…/Softcap.app/Contents/PlugIns/SoftcapWidget.appex

— a build inside the git worktree the rename was developed in, whose branch is
already merged into `main`. The checkout's own build of the same extension is not
registered, and cannot be: both bundles carry the identifier
`app.softcap.Softcap.widget`, and macOS keeps the path it saw first. Rebuilding,
relaunching and `pluginkit -a` on the checkout's bundle all left it unchanged.

**Why it is not urgent.** Both builds declare the same app group, so a widget
placed today reads the snapshot the running app writes — verified: four accounts,
under a minute old. It is running slightly older code, not wrong data.

**Why it is worth writing down.** When that worktree is removed — and it should
be, its work is merged — the registration goes with it and the widget disappears
from the gallery until the checkout's app is launched again. Someone will meet
that as "the widget vanished after cleaning up" and have no reason to connect the
two.

A second entry, `dev.example.StatusChecker.widget`, is registered from the same
worktree and is dead: nothing builds that identifier any more.

**Not acted on.** Removing another session's worktree is not this session's call,
and the worktree is locked. Left for whoever finishes the rename work.

## The landing's numbers are read back off the code

**Decision.** `TheLandingQuotesTheCode` holds four figures on the page against the
constants they came from: the two poll intervals, how long an account's name is
remembered, the notification thresholds, and the number of languages. Each check
has two halves — the constant still holds the value, and the page still quotes it.

**Why.** Prose goes stale the same way labels do, and twice now it has. The widget
cell claimed "every size" on both platforms when iPhone has a different set. And
the cost line said "two HTTP requests per Claude account per poll", which was true
when written and false a few hours later, because the profile is now asked for
once and remembered for six hours — a change made in this same session, by me,
without a thought for the sentence it falsified.

Both were caught by re-reading the page against the source, which works exactly
until nobody does it.

**What it cannot cover.** Claims that are not numbers. "It will not sign your CLI
out" is a description of behaviour that no assertion here can check; the tests
that cover it live next to the code that does it.

**One check leans on the compiler.** Removing a language does not fail this test —
it fails the build, because the enum's switches are exhaustive. Verified by trying:
the suite never ran. The half that does work is the page's, checked by making the
page say "Nine languages" and watching it fail. The scenario worth guarding is the
opposite one anyway: an eleventh language added while the page still says ten.

**Cost.** Four more places to update when a constant deliberately changes, each
naming the sentence it belongs to so the update is obvious rather than a puzzle.

## Two sentences sharpened, and one claim added that is worth making

**Decision.** Three edits to the landing's prose.

**A repeated shape.** "A monitor that logs you out of the thing it monitors is
worse than no monitor" is the page's best line. Four cells later it said "a
monitor you have to relaunch is not a monitor", which is the same joke told
worse. The second is now about what the app is instead: it never quits, so it
should not have to be quit to change a word.

**A sentence that said less than it meant.** "Credentials … are never written to
preferences, logs, or anywhere over the network" reads oddly — you do not write
to a network — and stopped short of the thing worth saying. It now says where
they *are* sent: only to the service each one belongs to, with no telemetry.
Checked before publishing: the only hosts in the sources are the two Anthropic
endpoints, the sign-in host, and a `localhost` callback. A grep for analytics
turned up nothing — the apparent hit was `sentry` inside `LimitsEntry`.

**A claim that had not been made.** The project has no third-party code at all:
every `dependencies:` in the manifest names a target inside it, the Xcode project
reaches one package and it is a local path, and every import is Apple's or this
project's. For an app that reads your keychain, that is worth a line on the page,
so it has one — and a test, because it stays true only until someone adds a
convenient line.

**Verified.** The dependency check was proved by putting `.package(url:` into the
manifest and watching it fail — in a comment, deliberately: a real bogus URL
stops SwiftPM from resolving and the test never runs, which proves nothing.

## The chart on the landing showed something that cannot happen

**Decision.** The illustration was redrawn as saw-teeth: each account's weekly
allowance spent through the week and back to nothing when the window renews, with
the accounts renewing on different days.

**Why.** The section says the chart draws the **weekly** window over a week or a
month. A weekly window resets every seven days, so over a month every line must
drop to zero four times. The illustration had one line resetting once, one rising
steadily for a month, and one flat — a shape no weekly window can take.

That matters more here than on most pages. The argument two sections up is that
the app does not draw a straight line across a gap because it would claim a
reading nobody took. An illustration that could not have been measured undercuts
exactly that, and a reader who understands rate limits well enough to want this
app is the reader most likely to notice.

**A better caption came out of it.** The picture now shows something worth
pointing at, so the words point at it: each tooth is one week, and the teeth do
not line up because the windows renew on different days — which is the thing that
tells you which account is fresh today. The old caption named a colour; the new
one names the account, and colours the name to match.

**Cost.** A denser picture. Sixteen teeth across four lines is more than the
previous drawing had in it, and "minimalist" was the brief. Kept anyway: real
usage looks like this, and a calmer picture would be calm because it was invented.

**Checked while there.** All four identity colours clear 4.5:1 against the page —
between 4.99 and 6.44 — so the coloured account name in the caption is readable
rather than decorative.

## The mock listed accounts in an order the window would not produce

**Decision.** The mock's rows run least loaded first, and a test keeps them that
way.

**Why.** The window sorts by the highest percentage across an account's windows,
ascending — so the account you can go and work in is at the top. The mock listed
peaks of 80, 39 and 100 in that order, which no run of the app would draw.

Corrected, it also tells the story the page is making: a Codex account with room
at the top, then one at 80% of its week, then one whose five hours are gone. That
is the promise in the second paragraph — "which account you should open next" —
illustrated rather than asserted.

**The guard caught its own fix failing.** The reordering script matched the three
rows, sorted them, and replaced the joined block — which never appeared in the
file, because the rows are separated by whitespace the pattern did not include.
It reported success and changed nothing. The new test read 80, 39, 100 on its
first run and said so.

**And the guard had a bug of its own.** It split the whole page on the row
marker, which leaves a last piece running to the end of the file — where the
chart's axis labels are `>100%<` and `>75%<`. The last row's peak would have come
from a gridline. It reads the mock's own markup now, the same block the label
checks use.

**Cost.** Two illustrations to keep in the same order: the page and the preview
image. Both were fixed, and only the page is checked — the preview is a rendered
PNG, and a test cannot read percentages out of it.

## The status item on the page was green; the real one has no colour

**Decision.** The menu bar strip in both mocks draws its ring in the surrounding
text colour, at the opacities the code uses — a full track at 35 % and the filled
part solid.

**Why.** `MenuBarGlyph` renders a **template image**. The system tints it: white
on a dark menu bar, black on a light one, dimmed when the bar is inactive. It
carries no colour of its own, and none of the load scale either — the mock drew a
green ring while the worst window in the same picture sat at 100 %, which in this
app's colour language would be red if it were coloured at all.

The design document does say the icon's colour follows the worst window. The code
decided otherwise and the code is what ships, so the page follows the code.

**What was already right.** The fill fraction: the strip draws 0.65 of the ring,
which is what `MenuBarGlyph` draws, and it draws one ring rather than two —
matching the rule that drops the inner one below 22 pt. The app icon in the
header is green with a white inner ring at 0.65 and 0.30, and those are the
generator's numbers exactly. Only the strip was wrong.

**Guarded.** A test reads the strip's markup alone and fails if any of the four
severity colours appears in it. Verified by putting the green back. The header's
icon is deliberately outside that range: it is a different mark and it is
supposed to be coloured.

## The two illustrations were of different machines

**Decision.** The chart draws three lines, named the same three accounts the
window lists, in the same order. A test compares the two.

**Why.** The window mock showed three accounts and the chart's legend named four
— `sam`, `sam.k`, `alex` and a `team` that appears nowhere else on the page. Two
pictures on one page, of two different setups, illustrating one paragraph.

Dropping the fourth also answers a note left when the chart was redrawn: sixteen
saw-teeth were dense, and "minimalist" was the brief. Twelve read more easily and
the picture is now no less true — it lost a line that should not have been there
rather than a line that was.

**Guarded.** The check reads the window's account names and the chart's legend
and requires the two sets to be equal. Verified by adding a fourth name back and
watching it fail.

**Also checked this round, and clean.** The page rendered through WebKit — the
engine the audience's browser uses, and the one every screenshot so far had
skipped — using Quick Look, which draws HTML with it. Identical to Chrome
throughout: the headline breaks in the same place, the mock and the strip are the
same, the chart's saw-teeth and the gap in `alex`'s line all survive. A negative
result worth writing down, so nobody repeats it wondering.

## The deploy rebuilds what it ships from

**Decision.** `site/deploy.sh` regenerates `og.png` and `favicon.ico` when their
sources are newer, before shipping anything.

**Why.** Both images are rendered from files beside them, and the entry that
introduced the preview said as much: "it has to be regenerated deliberately after
a copy change, and nothing enforces that." Nobody looks at their own link
previews, so a preview showing last week's headline is a mistake with no natural
moment of discovery.

**It found one on its first run.** The committed `favicon.ico` did not match what
`make-favicon.sh` produces — 4122 bytes against 3900. The committed one had been
built by an ad-hoc command with `--default-background-color=00000000`; the script
never had that flag. Without it Chrome paints the page white behind the mark, so
the corners outside its rounded square come out **white** — checked by decoding
the PNG and reading the four corner pixels, all `(255,255,255)`. On a dark tab bar
that is a white square with an icon inside it.

The flag is in the script now and the corners decode as fully transparent. The
file is 4122 bytes again, which is the committed one — so the script and the
artefact finally agree.

**Cost.** A deploy now needs Chrome when a source has changed. When nothing has,
it does not: the check is a timestamp comparison, and the script says plainly
which file is stale if it cannot rebuild it.

**Confirmed deterministic.** Two runs of the icon script produce byte-identical
output, so the rebuild does not add a spurious diff to every deploy.

## The core's portability is checked in three seconds, not in a build

**Decision.** `CoreStaysPortable` scans `Packages/Core` for AppKit anywhere, and
for any macOS-only framework imported outside an `#if os(macOS)`.

**Why.** The landing says the core is "a Swift package with no AppKit", and the
iPhone app is built out of the same modules — so it has to be true, not merely
true today. `make build-ios` already proves it, but only when somebody runs it,
and it fails somewhere inside a compile rather than naming the file.

The claim was verified before writing the test, which is the right order: no
AppKit in the core, and the one macOS-only import there — `CoreServices` in
`SessionWatcher`, for FSEvents — is behind a guard with a comment explaining why
the whole watcher has no meaning on a phone.

**How the guard reads the guards.** It counts `#if os(macOS)` against `#endif`
and flags a macOS-only import at depth zero. That is not a preprocessor and it
does not need to be: it answers one question about a handful of framework names,
and a file complicated enough to fool it would be worth reading anyway.

**Verified.** Both halves, by putting `import AppKit` and then `import IOKit` at
the top of a model and watching each fail.

**Also checked, and fine.** The page's search metadata: a 50-character title and
a 155-character description, both inside what a result actually shows.

## One row, drawn in four places, checked

**Decision.** `OneRowDrawnEverywhere` requires each of the four surfaces — the
limits window, the macOS widget, the iPhone screen and the iPhone widget — to
draw an account with `AccountRow`, and requires that view to be defined exactly
once.

**Why.** `AccountRow`'s own comment gives the reason: "a copy in two places would
drift apart on the first edit." The landing repeats the claim in its technical
notes. Four surfaces is exactly the count where copying starts to look
reasonable — a widget is cramped, a phone is not a Mac — and every copy would be
correct on the day it was made.

Verified before the test was written: all four import it from `StatusUI`, and the
only other `AccountRow` in the repository is a data row nested in the settings
pane, which is not a view and does not collide.

**The test found itself.** On its first run it reported two definitions of the
shared view, the second being this test file — which contains the string it
searches for. A check that fails because of its own text is worse than no check,
so it scans production sources only.

**Verified.** Both halves: by renaming the widget's call, and by adding a second
`struct AccountRow: View` beside it.

## The deploy verified one file out of six

**Decision.** `deploy.sh` now checks every file it shipped, by digest rather than
by status code.

**Why.** It fetched the page, confirmed a 200 and that the body said "Softcap",
and reported success. Five other files went with it. A deploy that dropped the
icon or the preview would have passed that check unchanged — the page answers,
the word is there, and nobody looks at the rest until somebody shares a link and
sees a bare URL.

A status code is the wrong instrument anyway: 200 proves something is being
served at that path, not that it is the thing that was sent. The check compares
the local file's SHA-256 against what the URL actually returns.

**Verified by breaking it.** `robots.txt` was replaced with a line of junk on the
server and the check reported "200 but serving something else" while the other
five matched. Then restored, and the next deploy confirmed all six.

The first attempt at that proof was itself wrong: it copied the script to `/tmp`
to skip the upload, which moved `$HERE` with it, so the digests were computed
against files that were not there. It printed nothing and the exit code came from
`grep`. The proof that counts ran the comparison with the real paths.

**Cost.** Six more requests per deploy, of files totalling 160 KB.

## Read the whole page, at last

**What was done.** The page was rendered and looked at from the top of the hero
to the last line of the footer. Until now only the parts under discussion had
been — the hero, the chart, the feature grid — and the technical notes and the
footer had never been seen rendered at all, only written.

They are right. The facts list reads cleanly, the footer's two lines land, and
nothing is broken or mis-spaced at the end of a long scroll.

**One thing removed.** `a { color: inherit }` — a rule for an element the page
does not contain. There is not a link on it anywhere: the app is not released,
the source is not public, and a button that goes nowhere is worse here than a
sentence saying so plainly. The rule is replaced by a comment recording that,
so the next reader knows it is a decision rather than an omission.

**Also checked, and clean.** Every class in the stylesheet appears in the markup;
the repository tracks nothing from a build directory; `.git` is 4 MB.

**Where this leaves the landing.** Each pass now turns up something smaller than
the last: this one found an unused CSS rule. What is left needs the owner — a DNS
record for `www`, a decision on HSTS, a sign-in to unblock the Cursor provider,
and the rename worktree cleaned up with the widget registration in mind.

## One unanswered keychain prompt disabled the whole app

**What happened.** The routine health check showed the snapshot 24 minutes old
against a five-minute poll. The app was running, four and a half hours up, the
window showing figures with nothing to say they were stale. Restarting it did not
help: the new instance never produced a reading either.

**The cause, from a stack sample.** A thread sat in `SecItemCopyMatching` inside
`SystemKeychain.read(service:)` — a synchronous keychain read waiting on a
SecurityAgent prompt nobody had answered. That call cannot be cancelled.

Two things then compounded it, and the second is much worse than the first.

**The guard never let go.** `refresh()` set a flag on entry and cleared it in a
`defer`. Correct, as long as the way out is reached. It is not reached by a
blocking call, so every later tick saw the flag, turned around, and the app kept
showing the same reading for as long as it was left open.

**And nothing was ticking anyway.** `start()` ran `await refresh()` and then
armed the timer. When the first poll blocked, the second half of that method
never ran: no timer, no Codex file watcher, no hot key, no wake handler. A single
unanswered prompt at launch left the app running and entirely inert.

**The fix, in two parts.** Everything is armed before the first poll, and the
first poll runs in its own task. And `RefreshGate` — in `Monitoring`, with nine
tests — lets a run start when nothing is running *or* when what is running has
been going longer than ninety seconds. The stuck run is not killed, because
cancellation does not reach a blocking call and pretending otherwise would be a
second bug; it is only no longer allowed to hold the door.

Ending takes a permit rather than being a bare call. A displaced run may still
return long afterwards, and a bare `end()` from that latecomer would open the
gate on the poll that replaced it — two polls at once.

**Verified on the running app.** Before: one thread in `SecItemCopyMatching` and
no timer. After: two, on distinct thread ids, ninety seconds apart — the app is
trying again on schedule and will recover by itself the moment the prompt is
answered.

**Still open.** The window says nothing about a poll being stuck. It shows the
last reading and the time it was taken, and a reader has to notice the time
themselves. Worth surfacing, and now possible: `wouldDisplace` is exactly that
condition.

## A test failed once and passed twelve times, which is worse than failing

**Decision.** The tests that wait for something now wait *for that thing*, up to a
generous deadline, instead of sleeping a fixed amount and asserting afterwards.
Three in the scheduler's suite and two in the watcher's.

**Why.** A routine check showed one failure in a full run. Six re-runs were clean,
and three more under artificial CPU load. A test that fails once and passes twelve
times is worse than one that fails every time: it teaches you to re-run rather
than to look.

The cause was structural rather than mysterious. The scheduler's tests slept 120
milliseconds and then asserted a run had started; the watcher's slept three
seconds and asserted an FSEvents callback had arrived. Both margins were tuned on
an idle machine, and the failing run happened during a build. The assertions were
about ordering — did this finish before that was allowed to start — and a
wall-clock margin is a poor way to ask that question.

**One kept its sleep, on purpose.** "Nothing more happens after `stop()`" has
nothing to wait for; it can only be given time and then checked. Its sleep went
from 250 ms to 400 ms.

**Verified.** The scheduler's suite ran ten times under eight-way load without a
failure, and the full package five times more. The important test still catches
the defect it was written for: removing the task separation in `PollScheduler`
makes it fail, now by exhausting its deadline rather than by a coin toss.

**A side effect worth having.** The suite went from 3.1 seconds to 2.1. The
watcher's tests had been paying three seconds each for events that arrive in a
fraction of one.

## The window spun for an hour and called it working

**Decision.** The popover's header shows how old the reading is, in the warning
colour, once it is older than three background polls. `readingAge` in `Monitoring`
makes that judgement; the view only renders it.

**Why.** Two ways of saying nothing, in the same corner of the window.

While a poll was in flight the header showed a spinner. A poll can block on a
keychain prompt and never return, so the spinner turned for as long as that
lasted — watched doing it for an hour. A spinner means "working on it", and it was
not.

And when no poll was running it showed the time the reading was taken, in grey.
`2:41 AM` is perfectly plausible at any hour; the reader has to work out for
themselves that it was an hour ago, and nobody does.

Past the threshold the age replaces both: `1 h 4 m old`, in the colour the app
already uses for trouble, with a tooltip saying a sign-in prompt may be waiting —
which is the usual cause and the one thing a person can act on.

**Three polls, not one.** A single missed poll is a slow network or a machine
waking up. Three in a row is a fault. The multiple applies to the *background*
interval, the slowest cadence, so a reading taken while the window was shut is
not called stale for having been taken then.

**Verified, and not.** Seven tests on the judgement, including an hour-old reading
reporting its age, a reading four minutes old being current against the
background cadence and overdue against the open-window one, and no reading at all
counting as current rather than stale — that is the empty window, which has its
own message. Not verified: how it looks. `NSPopover` does not open to a scripted
click, as this session found before, and chasing a screenshot means taking over a
screen that belongs to somebody.

## A poll no longer raises a dialog nobody is looking at

**Decision.** Keychain reads take a `promptIfNeeded` flag and default to `false`.
A poll passes `false` and gets `errSecInteractionNotAllowed` back as a
`ProviderFailure(.needsPermission)` instead of waiting. Only a refresh the person
pressed raises the flag, through `CredentialStore.setPromptAllowed`.

**Why.** Reading the CLI's keychain item means reading something another app owns,
and macOS asks the person once before allowing it. `SecItemCopyMatching` blocks
until that dialog is answered — and a dialog raised by a five-minute timer is one
nobody is looking for. It sat unanswered for eighty-four minutes with the app
frozen behind it, twice in one session. The owner's words the first time were
that they could not see the window at all.

`SecKeychainSetUserInteractionAllowed(false)` turns the wait into an immediate
error. It is process-wide, so it is set and restored around the single call; it
exists only on macOS, where the file-based keychain's access-control prompt lives,
and iOS has neither.

**A new failure kind, because the instruction differs.** `.needsPermission` reads
"Allow keychain access". Told "Sign-in required" a person signs in again, which
changes nothing. One `try?` was swallowing it into exactly that wrong advice and
now re-throws it; every other reason the CLI item cannot be read still falls
through quietly, because it means the account is simply not the active one.

**Result.** The app went from frozen for eighty-four minutes to a fresh reading in
thirteen seconds, three accounts current and the fourth reporting rather than
hanging.

**A correction to the previous entry.** It said the app "produces no unified-log
output at all", inferred from `log show` returning nothing. That inference was
wrong: `log show --last 1m` returns zero lines *of anything* from this shell, and
a marker written with `logger` cannot be read back either. The log is
unreadable here, not empty. The conclusion drawn at the time — that the timer was
never armed — was right, but it came from reading `start()`, not from the log.

**Also seen.** Inserting a case into the middle of `ProviderFailure.Kind` made an
incremental build report `.network == .needsPermission`. A clean rebuild passed.
Worth recognising rather than debugging.

## An account that cannot be read still has to be recognisable

**Decision.** `AccountRef` carries `lastKnownName`, the display name the store
already keeps, and `ClaudeUsageProvider` falls back to it rather than to the
account identifier when the profile cannot be read.

**Why.** A failed row read `claude/` followed by a UUID. That tells its reader to
sign in somewhere without telling them where, and the identifier is the one thing
about the account they have never seen. The store has held the name all along;
it simply was not carried through.

**Verified, and not.** Two tests: a failing fetch keeps the stored name, and an
account nobody has ever signed into still falls back to the identifier, which is
then genuinely all there is. Not verified on the live app — the account that
shows an identifier there has an empty stored name for reasons that could not be
inspected: reading the app's own keychain item from a shell hangs on the same
prompt this session has been working around.

**The guard caught the author.** The first draft of the doc comment pasted the
real identifier from this machine as an example. `NoPersonalDataInTheRepository`
failed on it. That is the whole point of that test and it is the first time it
has fired on something new.

## `make test` reported success on code that would not compile

**Decision.** The recipe runs under `set -o pipefail`, and retries once after
cleaning if — and only if — the *linker* was what failed.

**Why, for the retry.** Two API changes in Core in two iterations left the test
bundle linking against the previous mangled symbols: an added enum case made an
incremental build claim `.network == .needsPermission`, and a default argument
produced undefined symbols. Both times `swift package clean` fixed it in seconds,
after a diagnosis that need not have happened. A real error still fails the
second time.

**Why, for `pipefail`.** Piping `swift test` into `tee` makes the `if` read
`tee`'s exit status, which is always zero — so every run passed, including a run
where a source file did not compile. This Makefile had exactly that bug in its
build recipes and it was fixed there; writing the test recipe reintroduced it.

Caught by breaking a file on purpose and checking the exit code rather than
trusting that the retry was doing what it was written to do.

## Three places built the same row, and all three used the identifier

**Decision.** An account is named by `lastKnownName` wherever a row is built:
inside `ClaudeUsageProvider` before the profile answers, on its token-failure
path, and in `UsagePoller.placeholder` when a provider throws outright. The
identifier is the last resort and true only of an account nobody has ever signed
into.

**Why it took three passes.** The previous entry fixed one of them and reported
the live row still showing an identifier, with the stored name suspected empty.
It was not: a temporary probe written to a file — the unified log being
unreadable from this shell — showed the store holding `…@example.com` for the
very account in question. So the fallback was right and simply was not on the
path being taken.

The path was the first `catch` in `fetch`: when no token can be had at all, it
returned before the profile is ever asked for, passing `ref.id` explicitly. That
is exactly the account this was about — signed out, no token, nothing to ask
with. The poller's placeholder had the same literal.

**How it was found.** Not by reading harder. By checking the assumption: the
guess was "the stored name is empty", the probe said otherwise in one run, and
the question changed from *why is it empty* to *why is it not used*. Four tests
now cover the three paths and the genuine no-name case.

**Verified live.** The row that read `claude/` and a UUID for several iterations
now reads the account's mail address, still marked as needing a sign-in — which
is true, and now says which account to sign into.

**Written down twice, wrongly.** The first draft of this entry quoted that
address, and the repository's personal-data check failed on it. The entry before
this one did the same with an identifier in a doc comment. Both times the value
came from a live run being described in prose, which is where these leaks come
from: not from carelessness with test fixtures, but from writing down what was
just seen on screen. The check catches it; the habit to fix is describing the
value rather than quoting it.

## The check that ran too late

**Decision.** `NoPersonalDataInTheRepository` also runs as a pre-commit hook,
kept in `tools/hooks` with an installer, since `.git/hooks` is not tracked.

**Why.** The check found two leaks in two iterations and both times found them
*after* the commit: a real mail address in a decision entry and a real account
identifier in a doc comment. The pattern behind both is the same and worth
naming — neither came from carelessness with a fixture. Both came from
describing a live run in prose and quoting what was on screen. That is a thing
this project does constantly, and the moment it happens is the moment the guard
was not consulted, because the tests had already been run before the writing
began.

A quarter of a second on every commit closes that gap. `--no-verify` is there
for a reason to skip it.

**Verified.** By committing an address at a real domain and being refused, then
watching the same commit go through once it was gone.

**Still true of the history.** Earlier commits carry addresses that were removed
from the working tree afterwards. The repository is private; rewriting is the
owner's call and is only possible before it is not.

## The notifications switch said what the app wanted, not what it got

**Decision.** The answer to the authorization request is kept rather than
discarded, re-read whenever the Notifications screen appears, and shown there
when the system is not delivering.

**Why.** `_ = try? await centre.requestAuthorization(...)` threw the result away.
Denied — or never answered, which is what happens when the prompt appears behind
other windows for an app with no Dock icon — the app went on posting
notifications that went nowhere while the screen showed the feature switched on.
The switch was telling the truth about the app's intention and nothing about the
result, and those are different things.

It is re-read on every appearance because the answer can change in System
Settings at any time and nothing tells the app when it does.

**A false alarm on the way.** `defaults read com.apple.ncprefs` showed no entry
for the app, which looked like "never authorized" — the same shape as a fault
found earlier in this project, where the feature was dead and nobody knew. It was
not that: a probe written from inside the app reported `authorizationStatus == 2`,
authorized. The preferences store bundle identifiers in a form that grep does not
see. The check was worth doing and the answer was the good one.

**Also verified while there.** The statistics history is accumulating properly
under the renamed app group: 187 readings, the weekly windows of three Claude
accounts spanning eight and a half hours.

## The login-item switch was read once and then believed

**Decision.** The Updates screen re-reads `SMAppService.mainApp.status` whenever
it appears, and the toggle writes through `setLaunch` instead of reacting to an
`onChange`.

**Why.** `LaunchAtLogin` was already careful in the right way — its comment says
the state is read from the system rather than stored, because the user can turn
the login item off in System Settings and a stored value would then lie. The
screen then read it once, at view initialisation, and believed it from then on.
Switch the login item off elsewhere with this window open and the toggle says the
opposite of the truth, which is exactly the outcome the type was written to avoid.

**Why the binding changed too.** With an `onChange`, re-reading the system into
the state looks like the user flipping the switch, and registers the login item
again. Writing through the binding's setter keeps reading and writing apart.

**Swept for the same shape.** `launchAtLogin` was the only piece of view state in
the settings screens initialised from a system query; everything else is ordinary
UI state. The panes that show live data — accounts, statistics, notifications —
already reload when they appear, so this was the one place out of step.

**Not verified live.** Registering a login item changes the machine's
configuration, and that is not something to do to somebody's Mac in passing. The
change is a re-read and a binding; both compile and neither has a branch worth
guessing at.

## The reason a row failed, on hover

**Decision.** The failed row's message carries its `diagnostic` as a tooltip.

**Why, stated correctly.** The first draft of this entry claimed the diagnostic
was lost — that a log nobody can open is a place information goes to die. That is
wrong, and checking it before writing it down is what caught it: the diagnostic is
in `snapshot.json`, in the app group container, and reading it there is how every
poll failure in this session was understood. Not lost. Just kept somewhere no
person looks.

So the tooltip is a smaller claim than it started as: `Sign-in required` does not
say *why*, and the audience for this app is exactly the audience for
`refresh failed, HTTP 400`. Invisible until reached for, which is the right amount
of visible for a status code.

**What it revealed.** The one failing account reports `refresh failed, HTTP 400`.
That is the saved refresh token being rejected — and it is the exact loss the
design warns about, two entries up in the source: *"the copy must be taken on
every poll. Otherwise, once the user moves to another account, this one's token
is overwritten in the keychain and the account disappears from the list for
good."*

The app was frozen on the keychain prompt for hours. It could not take a copy
while that account was still active, the CLI moved on, and the copy it holds was
rotated away. So the keychain freeze did not only hide data for eighty-four
minutes: it cost one account permanently, and only a fresh `/login` will bring it
back. The row says so correctly.

**Where the tooltip does nothing.** Widgets and iOS have no hover. They show the
translated sentence alone, which is what they showed before.

## A token the server has finished with is dropped, not re-sent forever

**Decision.** `invalid_grant` on a 400 throws `RefreshRejected` rather than an
ordinary failure, and `CredentialStore` responds by clearing the saved copy. The
account stays in the list, marked as needing a sign-in.

**Why.** The previous entry found an account whose saved refresh token had been
rotated away while the app was frozen. Nothing about that changes: the token is
dead. But the app kept sending it — one request every five minutes, for as long
as the app runs, with a credential the server has already said is finished. A
client that does that indefinitely is a badly behaved one, whatever else is true.

The spec is unambiguous here, which is what makes the distinction safe to draw:
`invalid_grant` means expired, revoked or already rotated. Any other refusal —
`invalid_client`, a 500, an unparseable body — stays ordinary, because those can
change and the next poll is worth making.

**The account is not removed.** Removing it would hide the one thing the reader
has to act on. `syncWithCLI` gives it a working token again the moment they sign
in, and a test covers that round trip.

**Two existing tests had to change, and one of them mattered.**
`errorNeverEchoesTheToken` checked that a refusal does not write the token into
its own diagnostic — it used `invalid_grant`, which no longer produces a
diagnostic at all, so it would have quietly stopped checking anything. It now
runs over all three refusal shapes and asserts the property on whichever error
each throws.

**Verified live.** The failing row's reason changed from `refresh failed, HTTP
400` to `refresh token rejected; sign in again`, and the request is no longer
made.

## The screen promised accounts would appear, and said nothing when they could not

**Decision.** `syncWithCLI` keeps the keychain's refusal instead of swallowing it,
and the Accounts screen says so when it happens.

**Why.** The screen's subtitle promises that accounts signed into with `/login`
turn up on their own. Reading Claude Code's keychain item is how that works, and
a poll is not allowed to raise the dialog that grants it — deliberately, for
reasons two entries up. So when permission has not been granted the promise
quietly fails: the list simply stays short, with nothing to explain it and
nothing to do about it. The message names the action that works, which is
pressing Refresh, since that is the one path allowed to ask.

Every other reason to give up there stays quiet, because the ordinary one is that
Claude Code is not signed in at all, which is not a fault.

**The probe corrected the write-up.** This entry was going to say the case was
live: `SecurityAgent` was running, which looked like a pending prompt. A probe
from inside the app reported `blocked=false` and an ordinary failure — the
keychain reads fine, and the agent was left over from a `security` command of
mine that hung and was killed earlier. So the new line is correct and correctly
not showing.

**Also.** "no saved refresh token" became "no usable refresh token; sign in
again". After the previous change a rejected token is dropped, so the old wording
suggested the app had never had one when in fact it had one and the server
finished with it.

## The refusal had the wrong number, so nothing built on it ever ran

**Decision.** `KeychainRefusal.failure(for:)` maps both
`errSecInteractionNotAllowed` and `errSecAuthFailed` to `.needsPermission`, and
an account holding its own copy of a refresh token is no longer condemned by a
refusal about the CLI's item.

**Why.** Reading an item another app owns with user interaction switched off
returns **`errSecAuthFailed` (-25293)**, not the status whose name says so. The
detection added two iterations ago matched only the obvious one, so it never
fired: the refusal arrived as an ordinary read failure, the row advised signing
in again — the single action that cannot help — and the Accounts screen's new
explanation had no way to appear. Everything built on `.needsPermission` was
inert from the day it was written.

Found by probing the running app for the raw status: the CLI's item answered
-25293 while the app's own item answered 0. That second number is the other half
of the finding — this installation has never been granted access to Claude Code's
credentials, so the promise that `/login` makes an account appear has never
worked here.

**And correcting it broke three accounts, for a minute.** With the refusal finally
detected, the rethrow written for it fired everywhere: the CLI's item is one item,
so a refusal is refused for everybody, and three accounts that had been polling
happily failed at once. The refusal is now held rather than thrown, and used only
for an account that has no copy of its own — which is precisely the account that
can only be read through the item that was refused.

**Verified live at each step.** Before: three fine, one wrongly advised. After the
detection: all four failing. After the scope fix: three fine, and the fourth
naming the real reason. Six tests on the status mapping and two on the scope.

## The instruction became a button, and the catalogues grew a broom

**Decision.** Two changes, one leading to the other.

**The action sits next to the problem.** The Accounts screen told the reader that
Claude Code's credentials could not be read and then sent them to another window
to press Refresh. It is now a sentence and an `Allow access…` button doing the
same thing in place. A poll is not allowed to raise the keychain dialog — that is
settled and right — but a person pressing a button is exactly when it should
appear.

**Replacing the sentence orphaned it,** in all ten catalogues at once, and nothing
would have noticed. Adding a string is tidy: `tools/add_strings.py` puts it in
every language in one go. Removing one is not: the call site goes and the ten
entries stay. The existing check compares the languages against each other, and
ten copies of a dead key agree perfectly.

So `NoOrphanStrings` reads the English catalogue and requires every key to appear
as a literal somewhere in the sources. It found exactly one orphan — the sentence
just replaced — and nothing else, so the catalogues had been clean until today.
Keys composed at runtime (`%lldd` and its siblings, built from a unit) are listed
in the test rather than guessed at by the scan.

**Verified by adding a key nothing asks for and watching it fail.** That check
then caused a mess of its own: `git checkout` on the English catalogue to undo the
probe also undid the two keys added minutes earlier, leaving nine languages
holding strings the tenth did not — which the existing cross-language check
caught immediately. Both were re-added and the catalogues are level again at 140
keys each.

**Cost.** A key used only from a test, or reached by a spelling the scan cannot
see, will be called an orphan. The message says what to do about it.

## Two silences that looked the same

**Decision.** `CodexUsageProvider.discoverAccounts` returns an empty list only
when there is no `auth.json`, and throws when there is one that will not parse.
`UsagePoller` gives a provider it could not ask a row of its own instead of
skipping it.

**Why.** Both cases came out of a pair of `try?` as the same empty list, and an
empty list means the row is simply not there. No `auth.json` means Codex is not
set up on this machine and showing nothing is right. An `auth.json` that will not
parse means it *is* set up and something is wrong — and a row that disappears is
the worst possible way to say so, particularly for a file whose shape belongs to
somebody else. This project has already been caught out once by an upstream
change of shape, in the very same file's sibling.

The poller then swallowed it a second time: `guard let refs = try? …  else
{ continue }`. Even a thrown failure produced silence. It now names the service —
`Codex`, from the brand name that is never translated — with no account to name.

**What prompted the look.** Yesterday's finding was that everything built on
`.needsPermission` had been inert because the status never matched. That is worth
generalising, so every failure kind was checked for a real producer. All five have
one. But two of them were being produced into a `try?` and lost, which is the same
disease at the other end.

**An existing test had to change, and its name survived.**
`oneBrokenProviderDoesNotHideTheOthers` asserted the working provider's accounts
were the *only* result — the old silence, written down as an expectation. The
claim in its name still holds and is now checked properly: the working account is
present, and the broken provider reports rather than vanishing.

## Changing the account list and saving it are one act or neither

**Decision.** `forget` and `addLoggedInAccount` go through `changing(_:)`, which
puts the list back if the keychain write fails, and lets the failure through.
`syncWithCLI`'s call site logs instead of discarding.

**Why.** A sweep of every `try?` in the sources, prompted by the last two days:
one failure kind was inert because a status never matched, two others were
produced straight into a `try?` and lost. Fifty places use `try?`; most are
parsing with a documented fallback and are fine. Three were not.

**The list and the keychain could disagree.** Both operations changed the array
and then persisted it as separate steps. When persisting failed the change had
already happened, so the window showed one thing and the keychain held another:
an account forgotten until the next launch brought it back, or one added by a
browser sign-in that was gone by morning. Whichever way round, the app looked
right and was not.

**The token copy failed silently.** `try? await store.syncWithCLI(…)` is how an
account keeps a copy of its refresh token while it is still the active one, and
that copy is the entire reason a plan stays visible after `/login` moves on. A
failure there is invisible until the switch, and by then the account is gone for
good — which this session has already watched happen, from a different cause. The
next poll retries, so a passing failure costs nothing; it is now logged, and gets
no banner of its own because a lasting one means the app cannot write its own
keychain item, which the rows would already be saying.

**And one silence that was not.** `SharedStore.write` reports a failed write with
a comment explaining that the symptom is a widget quietly showing yesterday's
numbers — but the encode a line above it said nothing, with the same symptom. It
reports now too.

**A doc comment had been orphaned.** A test helper added yesterday landed between
`addLoggedInAccount`'s comment and the function, so the comment described the
wrong thing. Put back.

## The permission is written down, in both places

**Decision.** The README gains a section on the one permission the app needs, and
the landing gains a paragraph about it in the section on not signing the CLI out.

**Why.** Reading what Claude Code is signed into means reading a keychain item
another app owns, and macOS asks once. That is now a real step in the first-run
experience — the app reports the refusal, names the action, and offers the button
— and nothing said so anywhere. Somebody meeting "Allow keychain access" for the
first time had no document to check.

On the landing it belongs where it is for a different reason. A developer reading
that this app reads Claude Code's credentials will think about their keychain
within a sentence or two. Answering the question before it is asked is worth more
here than the half-line of friction it admits to.

**Also said, because it is the reassuring part.** Until the permission is granted,
accounts added through the browser work anyway: they carry their own tokens and
never touch the CLI's item.

**The sweep that led here finished clean.** Every `catch` in the sources either
handles its error or carries a comment saying why the silence is right. The
`try?` sweep the day before found three worth fixing out of fifty; this one found
none, which is the answer worth having.

## The iPhone widget was still spelling percentages by hand

**Decision.** `PhoneWidgetView` uses `Localization.percent(_:)`, and a test
forbids a `%` written immediately after an interpolation anywhere but the file
that decides where the sign goes.

**Why.** Four of the ten languages disagree with `"\(n)%"`: Russian, French and
Spanish separate the sign with a non-breaking space, Arabic wraps it in
directional marks. That was found and fixed across the app some time ago — six
places, all of them — and the iPhone widget kept doing it by hand through every
edit since, because nothing was watching.

**How it surfaced.** Not by looking for it. By auditing a different rule: that no
text shown to a person is written outside the catalogues. Sweeping for `Text("…")`
with a bare literal turned up eight, of which six are brand names, plan names or
bare numbers — all correct — and two were percentages built with a sign.

**The pattern the test forbids** is a `%` directly after a closing interpolation.
Format specifiers never look like that, so `%@`, `%lld` and `%1$@` pass
untouched, and the file that writes the sign on purpose is named as the one
exception.

**Verified** by putting the hand-built percentage back and watching it fail.

## Two commands called Refresh, one of which could not do what the other did

**Decision.** One method, `refresh(_ origin: PollOrigin)`, with no default. Every
call site says whether a timer or a person set the poll going, and the compiler
will not let one be omitted.

**Why.** There were two methods, `refresh` and `refreshNow`, differing by whether
the keychain may raise its dialog. The window's Refresh button called the second.
The context menu's Refresh — the same word, and the one the app's own message
tells people to press — called the first, and so could not do the thing the
message promised. The refresh hot key was the same.

A name one letter apart is not a choice anybody makes deliberately; it is a
choice made by whichever line was copied. Written as an argument, the call site
reads as what it is: `refresh(.person)` beside a button, `refresh(.timer)` inside
a scheduler.

**Removing the default is the point.** With `= .timer` the old bug could recur by
omission, silently. Without it, every new call site is a decision the compiler
insists on — which is a better guard than a test, because it cannot be forgotten.

**The two that are not obvious.** The poll after forgetting an account passes
`.timer`: the person asked to forget one, not to be asked for permission to read
another. The first poll at launch is `.timer` too — nobody has asked for anything
yet, and it is the poll that used to freeze on an unanswered dialog.

**How it surfaced.** By finishing yesterday's audit of every path text takes to a
person — tooltips, menu items, alerts, notifications, spoken labels. All of it is
localised, which was the answer sought; the menu's Refresh calling the wrong
method was what the reading turned up on the way.

## The language chose the words and the system chose the numbers

**Decision.** Every root view that takes its writing direction from the chosen
language now takes its locale from it too, and a test requires the pair.

**Why.** A language setting decides more than which words appear: whether a clock
reads 2:41 AM or 14:41, which digits are used, how a date is ordered. Two places
already knew that — the staleness badge and the spoken summary both build a
`DateFormatter` with `activeLocale`. Everywhere else handed a `Date` to SwiftUI,
which formats in the *system's* language.

So with a language chosen in settings, the badge said one thing and the clock
beside it another, in a different tongue. The percentages had been found and
fixed by hand months earlier; the dates had not, because nothing tied them
together.

**The rule the test encodes** is the pairing, not the fix: a view that follows the
language for direction must follow it for formatting. They are one setting and
they are forgotten one at a time — every root view set the first and none set the
second.

**The chart is exempt on purpose,** and the test says so rather than leaving the
exemption to look like an oversight. It pins its direction left-to-right because
an axis is not text, and a mirrored one reads a rising line as falling. Its
labels still follow the language: it inherits the locale from the screen it sits
in.

**How it surfaced.** By taking the previous finding's shape and applying it to the
neighbouring rule. Percentages had one formatter used everywhere but a widget;
durations turned out clean, every one of them going through `loc.remaining`; dates
were the third and were not.

## The empty window gave the one instruction that could not help

**Decision.** With no accounts and the keychain refused, the window says so and
offers the same `Allow access…` button the Accounts screen has. Otherwise it goes
on saying "Sign in to Claude Code or run Codex".

**Why.** That sentence is right advice exactly when it is not the problem. On a
machine where Claude Code is signed in and the keychain has not been allowed —
which is every machine until somebody allows it — the list is empty for a reason
the reader has already dealt with. Being told to do it again is worse than being
told nothing: it sends them off to repeat the one step that was never missing.

This is the first thing a new user sees, and this week's work is what created the
trap: the app used to read the CLI's item without asking, so an empty list really
did mean nobody was signed in.

**No new strings.** Both sentences and the button already exist in the ten
catalogues, from the Accounts screen. Reusing them keeps the wording identical in
the two places a person can meet the same problem, and adds no translation work.

**The other two empty states were checked and are right.** The iPhone says to
sign in on the Mac, because tokens reach it through the iCloud keychain and there
is nothing to sign into there. The widget says to open the app, because a widget
cannot fetch anything itself.

## An instruction that names a path grows stale with the operating system

**Decision.** The two messages that sent a reader into System Settings name the
pane rather than the route: "Check Login Items in System Settings", "Turn them on
under Notifications in System Settings".

**Why.** One of them was already wrong here. It said
`System Settings → General → Login Items`, which was right on macOS 14 and is not
on macOS 26, where that pane is called Login Items & Extensions. An instruction
precise enough to be wrong is worse than one general enough to stay true — the
reader follows it, does not find what it names, and doubts the rest.

They also disagreed with each other typographically, one arrow and one chevron
for the same idea, which is the sort of thing that only shows up when the two are
read side by side.

**What was wanted instead, and why it was not done.** A button opening the pane
directly would sidestep naming altogether — the same move as yesterday's `Allow
access…`. macOS has URLs for it. They were not verified, because verifying meant
launching System Settings, and System Settings was already open on this machine
with somebody's work in it. An unverified button that might do nothing is worse
than a sentence that certainly says something, so the sentence it is.

**How it surfaced.** By listing every string in the catalogue that tells a person
to do something and reading each against the states it appears in. Most were
right. Yesterday's empty-window advice came from the same list, one entry above.

## Percentages smuggled past the formatter in a format string

**Decision.** The sentences that mention a percentage take it as `%@`, already
spelled by `Localization.percent(_:)`, instead of writing `%lld%%` and leaving
each catalogue to place the sign.

**Why.** The formatter exists because four of the ten languages disagree with
`80%`: Russian, French and Spanish separate the sign with a non-breaking space,
Arabic wraps it in directional marks. Code had been swept for that twice. But a
format string is not code — it is ten strings, each of which has to remember the
rule on its own, and three did not:

    ru  "%@: %lld %% лимита"    a space, but an ordinary one
    fr  "%@ : %lld%% de la limite"    none, and French wants one
    es  "%@: %lld%% del límite"       none, and Spanish wants one
    ar  "%@: %lld%% من الحد"          no directional marks

Passing the number through the formatter first means no catalogue has to know.

**And the notification said something untrue.** Below 95 the body read "Less than
a fifth left" — right for the default threshold of 80 and for no other, while the
thresholds are the reader's to add and remove. Set one at 50 and it claimed a
fifth. It now works the remainder out: *About 20% left*, spelled by the same
formatter.

**A test was asserting the bug.** `everyLanguageProducesANonEmptySentence` checked
that each of the ten sentences contains `"45%"` — English typography, demanded of
all of them. It passed only because the sign was being written by hand. It now
asks for the share as that language spells it, and the fix is what made it fail.

## The guard that could not see the catalogues

**Decision.** `PercentIsAlwaysFormatted` gains a second test, reading the ten
catalogues: a translation may not contain the percent sign at all. The share
arrives as `%@`, already spelled.

**Why.** The first test looks for `)%` in Swift — a sign written right after an
interpolation. It was added after the iPhone widget was found still building
percentages by hand months later, and its comment says as much: the rule had
been applied twice and nothing was watching.

Then the same bug came back through the door the test does not face. A format
string is not Swift, so `"%@: %lld%% of limit"` sailed past — and behind it, ten
translations each having to remember where its language puts the sign. Three did
not.

The lesson is narrower than "add a test": the guard was written against the
shape of the last bug rather than against the rule. `)%` is one way to misspell a
percentage; the rule is that only the formatter spells it.

**Cost.** A catalogue can no longer show a percent sign in any other sense — a
literal "50% off" would be refused. Nothing in this interface says such a thing,
and refusing it wrongly is a visible test failure with the line in the message,
which is cheaper than three languages quietly misspelling their own typography.

**Verified.** Both wrong forms rejected — the escaped `%%` inside a format string
and a bare sign after a number — and the correct `%@` form accepted, by writing
all three into the French catalogue and running the suite on each.

## The landing stated a default as though it were the behaviour

**Decision.** "A notification at 80% and 95%" becomes "at 80% and 95% out of the
box, at whichever levels you set instead".

**Why.** The Notifications pane has a field for adding a level and a cross for
removing one. 80 and 95 are what ships, not what the app does. A reader deciding
whether this fits them was being told the levels are fixed — and someone who
wants a warning at 50 would conclude it cannot.

This is the second time in one sitting that the defaults were mistaken for the
rule. The notification body said "less than a fifth left" below 95, which is true
of the 80 that ships and of no other level. Same error, two places, found by
asking the same question of the prose that had just been asked of the code.

**And the test was pinning it there.** `LandingQuotesTheCode` asserted that the
page contains the string "80% and 95%" — describing the wrong sentence
faithfully. It now also requires "out of the box", so the qualification cannot be
dropped again. That is twice today a test held a mistake in place by asserting
what the code happened to produce.

**Cost.** A longer sentence in a section built of short ones.

**Also checked, and correct:** four widget sizes on macOS and the two accessory
shapes on iPhone's lock screen, both as claimed; quiet hours mutes the
notification but records the reading, so nothing is delivered late in the morning
to make up for it — which is what the page says.

## Sweeping for the same mistake everywhere it could be

**Decision.** Having found the defaults stated as the rule twice, the whole class
was swept: every field of `Preferences` that reaches a control in Settings was
checked against what the landing and the README say about it. Two more were
wrong, and both are now written as dials.

**What the sweep found.**

*The poll intervals.* The page said "five minutes apart in the background, once a
minute while the window is open" — inside the section headed "Cost of running
it". Both are settable, anywhere from thirty seconds to an hour. That is the
section a reader uses to weigh what this costs, so "you can ask less often" is
precisely the answer somebody there is looking for, and it was missing.

*The menu bar.* "The icon carries … how long until it frees up" describes the
`timer` default; the strip can carry the percentage instead, or both, or the icon
alone.

**What was checked and is right.** Language ("Follows the system by default"),
appearance, row layout, ordering, snapshot age, recovery notices, window scope,
quiet hours, the hot keys, the Codex root — none of these are described anywhere
as fixed. The history-keeping figures (a point of movement, five minutes, half an
hour, 35 days) are not settable, so stating them flatly is correct.

**Cost.** Three sentences longer. The alternative was a page that quietly
under-sells the app to the reader most likely to care about the number.

**Verified.** The guard rejects the page with either qualification removed; the
live page carries both.

## Hiding an account showed it as an outage instead

**Decision.** The statistics chart is drawn from the accounts the person has not
hidden, and names them from the credential store rather than the live snapshots.

**Why.** Hiding an account removes it from the poller, so nothing more is
recorded for it. The chart drew the history unfiltered, so its line stopped at
the moment it was hidden — and a stopped line means, in every other part of this
chart and in the sentence on the landing page explaining it, that nothing was
measured. Someone who hid an account was shown their own choice as an outage.

**And the legend printed a UUID.** Names came from `appModel.snapshots`, which
holds only the accounts that answered this poll. Anything in the history and not
in that set fell through `names[id] ?? id` to its identifier — `claude/` and a
UUID, on screen. Hidden accounts fell into it by construction; so does one that
failed to poll this launch, and one that was forgotten.

Two fixes, because they are two faults. The names now come from
`store.accountStates()`, which knows an account whether or not it answered, with
the live snapshots merged over the top for Codex, which is not in the store. And
the fallback, for an account genuinely unknown, is the service: we know it was
Claude, we do not know whose. Brand names are not translated, so this needs no
catalogue entry.

**Cost.** `segments` and `accountIDs` gain an `only:` parameter, defaulting to
nil — no caller outside the pane changes. The history keeps hidden accounts'
samples, so unhiding restores the line rather than starting it over; hiding is a
view, not a deletion.

**Verified.** Both fixes were reverted one at a time and the new tests fail on
each. The id chain the names fix depends on was traced rather than assumed:
`snapshot.id`, `ref.id` and `account.id` are the same string.

**A wrong experiment, recorded because it looked right.** Hiding was first
"verified" by writing a `hiddenAccounts` key with `defaults write` and counting
the accounts in the shared snapshot — which did not change. The conclusion nearly
drawn was that hiding is broken. The settings are stored as one JSON blob under a
single `preferences` key, so the stray key was never read by anything. An
experiment that changes nothing observable is not evidence that nothing changed.

## The stale-build retry now covers the other stale-build message

**Decision.** `make test` retries after `swift package clean` on "missing
required module" as well as on a link failure.

**Why.** The directory was renamed from `softcap` to `softcap` and the
build cache still held the old absolute paths, so the suite failed with
`missing required module 'SwiftShims'` — nothing to do with any code. The retry
existed for exactly this and did not fire, because it was written against the two
messages seen at the time.

Same shape as the percent guard written against `)%`: the rule is "a stale cache
produces nonsense that reads as a code error", and the condition listed the
symptoms instead.

**Cost.** A genuinely missing module now costs one clean-and-rebuild before the
failure is reported.

## The README offered a download that had never existed

**Decision.** The machine-managed block in the README says there is no published
build, and the prose around it stops speaking in the present tense about releases
that have not happened. A test requires the README and the landing to agree.

**Why.** The block advertised `releases/latest/download/Softcap.dmg`, and the
sentence under it said "every push to `main` publishes one". Asked for, that URL
answers **404**. So does the repository page and the releases page: the repository
is private and no release has ever been published.

The release workflow is real and does run on every push. Every run has failed, in
three to five seconds, and the reason is the same each time:

    The job was not started because recent account payments have failed or your
    spending limit needs to be increased.

GitHub Actions is stopped on billing. That is the owner's to fix and nothing in
this repository can. What this repository can do is stop claiming the result.

**The landing was already right.** It says "in development" and offers no link —
correct, and correct for the same reason the README was wrong. The page had no
download link and no decision entry saying why; it turns out there is simply
nothing to link to.

**The guard.** `TheReadmeAndThePageAgreeOnAvailability` asserts that exactly one
of two things is true: the page says "in development", or the README offers a
download. It needs no network, because the invariant is agreement rather than
reachability. When a release is finally published, the workflow rewrites the
README block — and this test then fails until the page stops saying the app is in
development, which is what should happen.

**Checked so the next attempt is not another round trip.** The workflow degrades
without signing secrets: no certificate configured, and none is — `gh secret
list` is empty — so it takes the ad-hoc branch and says so in the release notes,
which is what the README describes. And the rewrite still finds its markers: the
substitution was run against the new block and replaced it cleanly.

**Cost.** The README's first section now says the app cannot be downloaded, which
is a worse first impression than a link — and a better one than a link that 404s.

## The phone widths were never actually rendered

**Decision.** `site/check-widths.sh` renders the page at 320, 360, 390, 430, 768
and 1024 px and fails if anything is wider than its viewport. `deploy.sh` runs it
before shipping, when Chrome is present.

**Why.** An earlier entry recorded, honestly, that below 485 px nothing could be
checked because headless Chrome on macOS will not open a window that narrow, and
that the narrow-screen rule was therefore "reasoned rather than seen".

That is worse than it sounds. `--window-size=320,600` is not refused — it is
**clamped**. The page reports a 500 px viewport, no media query below 500 fires,
and the screenshot is still written 320 px wide because it is scaled afterwards.
So a phone render looks exactly like a phone render and is a 500 px desktop one.
Both headless modes do it; this was checked rather than assumed.

An iframe carries its own viewport for media queries, so a 320 px iframe inside a
wide window is a true 320 px render. With `--allow-file-access-from-files` the
parent can read each frame's document directly, so the measurement needs no
messaging and no waiting — the parent's load event already fires after its
frames.

**The result.** Nothing overflows at any of the six widths. The rule that was
arithmetic is now something that has been seen, and it stays seen: a deliberate
900 px block makes the check name the element and stops the deploy before a
single file is copied, verified by doing exactly that and then confirming the
live page was untouched.

**Cost.** The deploy needs Chrome for one more thing. It already wanted it for
`og.png` and the favicon, and says so and continues when it is absent — the new
check does the same rather than blocking a deploy on a browser.

**Verified the instrument before the subject.** A probe page reporting
`clientWidth` and two media queries showed 320 with both firing in a narrow
frame, and 1100 with neither in a wide one. This is the fourth measurement this
session that had to be checked before it could be believed, and the second that
was wrong when first written.

## The page nobody visits was the one with the caching rule

**Decision.** The Caddyfile matches both spellings of the document —
`@page path / /index.html` — and `deploy.sh` checks `Cache-Control` on the live
URLs after every deploy.

**Why.** The Caddyfile said `header /index.html Cache-Control "no-cache"`, and
Caddy applied it faithfully. A `header` matcher tests the **request** path, and
everybody arrives at `/`. So:

    /            no Cache-Control at all
    /index.html  no-cache
    /og.png      public, max-age=604800

The one document that changes had no caching instruction, while three assets that
never change carried a week of it. Without the header a browser falls back to
heuristic freshness — a fraction of the time since `Last-Modified`, which *grows
as the page gets older*. A landing edited five times in an evening would be
current; the same page a fortnight later could be held for hours. Which is
exactly what `no-cache` was written to prevent, and it was there, one path away.

**Why the existing checks could not see it.** `deploy.sh` compares a SHA-256 of
every served file against the live URL — thorough about bytes, and the bytes were
never wrong. Nothing looked at a header. So the verification step now asserts the
two documents say `no-cache` and the three assets say a week, on the URLs people
actually request rather than the ones the config names.

**Cost.** Five more requests per deploy, and a deploy that fails when a header is
wrong even though every file is correct — which is the point.

**Verified.** The old matcher was put back and shipped: the deploy reported
`Cache-Control is 'absent', expected 'no-cache'` and exited 1. Then restored, and
the assets still carry their week — the named matcher does not over-reach.

**Left alone deliberately.** `robots.txt` and `sitemap.xml` carry no
`Cache-Control`; crawlers apply their own policy and a stale copy of either is
harmless. The sitemap has no `lastmod`, which is right for a page whose date
nobody would remember to update — an unmaintained date is worse than none.

## Both widgets printed the current time beside data of any age

**Decision.** A widget shows `snapshot.capturedAt` — when the app took the
reading — and past `readingAge`'s tolerance shows the age instead, in the same
words and the same colour the window uses. A test forbids printing `entry.date`.

**Why.** Both widgets rendered `Text(entry.date, style: .time)` in the header.
`entry.date` is the moment WidgetKit built the timeline entry: now. The
percentages come from a file the app wrote whenever it last ran. So a Mac that
had been asleep, or a phone whose app had not been opened in a week, showed last
week's figures under this minute's clock — asserting a freshness the numbers do
not have.

The comment above the timeline says "the system may defer the refresh — which is
exactly why the snapshot age is shown". The intent was written down; what got
shown was the refresh time.

The window next door had already reasoned this out, and says so: *"`2:41 AM` is
perfectly plausible and says nothing."* Its `freshness` view shows the age in the
hot tint once overdue and the reading time otherwise. The widgets now say the
same thing in the same words — `"%@ old"` already existed in all ten catalogues.

**Counting from `entry.date` stays.** A reset counts down from now, so
`window.remaining(from: entry.date)` is right. The rule is narrow: count from it,
do not print it. The guard is written that way — it looks for `entry.date, style:`
and separately requires each widget to work out an age at all, since a widget
that simply stopped asking would pass the first half.

**Cost.** `SharedSnapshot` carries `pollingEvery`, so a widget can tell recent
from overdue against the interval its owner actually set rather than a guess.
The field is optional: a snapshot written by an older build must still decode,
because a widget that cannot read the file falls back to "No accounts found" —
a lie about the accounts, told because of a field. Proved against the real file
on disk, which has exactly the four older keys, and by making the field required
and watching the test fail.

**Verified, and not.** Both guards were checked by reintroducing each fault. The
live app now writes `pollingEvery`. What has *not* been looked at is either widget
rendered in its overdue state — the small layout gives the age the title's place,
which is reasoned from the window's rule rather than seen. The first probe of the
second guard was itself wrong and reported a pass that was not one; it was redone
until it failed for the right reason.

## The phone showed hour-old figures and said nothing

**Decision.** The iOS app polls again when it comes back to the foreground, and
its screen shows when the figures were taken — the age in the hot tint once
overdue, the reading time otherwise, the same words as the Mac window.

**Why.** `.task { await model.start() }` runs once, tied to the view's lifetime.
A phone suspends and resumes with the same view, so returning to the app after an
hour showed hour-old percentages: no spinner, no timestamp, nothing to suggest
pulling to refresh. `PhoneModel` had published `lastUpdated` all along and no
view read it.

The Mac had already worked this out twice over — `readingAge`, and a `refreshAfterWake`
setting for the machine waking from sleep. The phone reuses that setting rather
than inventing a second one: coming back to a suspended app is the same idea.
`refreshOnReturn()` also declines on the first activation, when `start()` is
already polling, so a launch is one poll and not two.

**The guard was widened rather than extended.** It began as "both widgets work
out the age", written the same week around the two places a bug had been found.
It now covers all four surfaces — window, both widgets, phone screen — and the
phone is precisely the one the narrower version would have missed.

**Verified.** Seen, not reasoned: the app was built and run in a simulator and
the reading time renders in the toolbar. Getting there needed the next entry.

## `GREP_OPTIONS=--color=always`, and a UDID full of escape codes

**Decision.** `make run-ios` finds the simulator with `sed`, and refuses anything
that does not look like a device id.

**Why.** It had been failing with

    Invalid device: A5DDD836-17D1-4310-B6BF-48F9CAD92662

three times per run, naming a device that boots perfectly by hand. The id was
correct. What was wrong was invisible: this machine sets
`GREP_OPTIONS=--color=always`, so grep emits ANSI codes whether or not anything
is watching, and a UDID captured through `$(… | grep -oE …)` arrives wrapped in
them. The terminal then rendered those codes as the colour they are, which is why
the error looked like it named a plain UDID.

It reproduced only inside `make` — the interactive shell resolves grep
differently — which is what made it look like a Makefile bug rather than an
environment one. `od -c` on the captured value inside a probe makefile settled
it in one shot.

**Cost.** `sed` instead of `grep`, which is one pipe shorter anyway, and a `case`
that rejects a malformed id with the string printed through `cat -v` so the next
person sees the escapes instead of the colour.

**Swept.** These were the only two captures of grep output in the repository;
everywhere else it is `grep -q` or `grep -c`, where the exit status or a count is
what matters and colour cannot reach. Display-only greps keep their colour.

**A note for anything else run here.** The variable is set for the whole
environment, so any script that parses grep output on this machine has the same
trap waiting. It is not this repository's to fix, and it is worth knowing.

## The link preview had nothing tying it to the page

**Decision.** Tests require `og-template.html` to repeat the page's headline, the
same three accounts, and the same answer to whether Softcap is in development.
Both drawings must also draw every bar as long as the number beside it.

**Why.** `og.png` is rendered from the template, and `deploy.sh` re-renders it
when the template is newer. Nothing connected either to `index.html`. The entry
that introduced the template said so plainly — "it has to be regenerated
deliberately after a copy change, and nothing enforces that" — and left it there.
Edit the headline on the page and the preview keeps the old one, silently,
because nobody looks at their own link previews.

The fix works from the other end, and closes the loop by itself: the template has
to repeat what the page says, so changing the page forces changing the template,
which makes the template newer than the image, which makes the deploy re-render
it. Nothing has to be remembered.

**And the bars.** A drawing of a window is worth its agreement with the window. All
twelve fills — six on the page, six in the preview — were measured against the
number printed beside them. Eleven match exactly. The twelfth is a bar labelled
0% drawn 2% wide, and that is right: `AccountRow` sizes a bar
`max(2, width * percent / 100)`, so an unused window shows a stub rather than an
empty track, and both drawings do the same. The test allows that one case and
nothing wider.

**Also.** The page said "the window says how old it is". Since yesterday both
widgets and the phone say it too, so the sentence now names all four. That is the
sort of claim that only ever gets weaker with time, so it is worth the words: an
interface that admits its data is stale is unusual enough to say out loud.

**Verified.** Each half of each guard was checked by making the two files
disagree — a changed headline, a renamed account, a status only one of them
carries, a bar at two thirds, a zero with no stub. One probe reported a pass that
was not one, because "in development" appears twice on the page and only the
first was replaced; redone until it failed for the right reason. The regenerated
`og.png` came out byte-identical to the committed one, so the render is
deterministic — which is why a spurious re-render costs nothing.

## Would the site come back after the host reboots?

**Decision.** `deploy.sh` checks two things it never checked: that the domain has
reached kamal-proxy's saved state, and that the running container's restart
policy is `unless-stopped`.

**Why.** Everything about this deploy is verified except what happens when the
machine stops. The digests prove the right bytes are served; the headers prove
the right instructions come with them; nothing looked at whether any of it exists
after a power cycle.

The chain was walked link by link:

    docker, containerd     enabled at boot
    softcap-site           restart: unless-stopped, and so on the live container
    kamal-proxy            restart: unless-stopped
    the route              in kamal-proxy.state, on a named volume
    the certificates       in the same volume
    the files              bind-mounted from disk
    disk                   107 GB free of 154 GB

All sound. But the host has been up seventeen weeks, so none of it has been tried
end to end, and it will not be tried here: other people's services run on this
droplet, and rebooting somebody's production host to satisfy a hypothesis is not
a deploy script's business, nor mine. **This is verified by construction and not
by experiment, and that distinction is the point of writing it down.**

**What the two new checks are for.** They are the links that can drift silently
while everything still works. A route registered but not written to the volume
serves perfectly until the reboot that loses it. A container started by hand once
keeps running with whatever policy that command gave it, which the compose file
would not reveal. Both fail loudly on the next deploy now rather than on the next
reboot.

**Cost.** Two more ssh round trips per deploy, and a deploy that fails when the
site is serving correctly — which is exactly when this is worth knowing.

**Verified.** The state check was run against a domain that is not registered and
refused it, and against `softcap.app` and accepted it. A full deploy with a
fabricated domain was deliberately *not* run: it would have registered a junk
route on a proxy that serves other people's sites.

## The README quoted the code and nothing checked it

**Decision.** `TheReadmeQuotesTheCode` reads the constants and requires the README
to name them: the sampling rule, the retention, the count of settings sections,
the widget families, the number of catalogues.

**Why.** The landing has been guarded this way since it was written, on the
principle that a page quoting the code is worth nothing once the code moves. The
README makes exactly the same kind of claim — one reading kept when the figure
moves by a point, at most every five minutes, one every half hour regardless,
pruned after 35 days, seven sections, four widget sizes, ten languages — and
nothing was watching any of it. It is the first thing anybody reads here.

Every figure was checked by hand first and every one was right, which is the
usual state of a document nobody has broken yet.

**Counted rather than stated where possible.** The sections are counted from the
pane files and the languages from the `.lproj` directories, so adding an eighth
pane or an eleventh language fails here rather than quietly making a sentence
wrong.

**A note on wrapping.** The first version failed on "moves by a point", which is
in the README, split across a line break by the 80-column wrap. Whitespace is
collapsed before matching — the same thing the preview guard had to learn. A file
being tidy is not a sentence being wrong.

**Verified.** The retention was changed to 60 days in the code and the guard
refused it; the sampling interval to ten minutes, likewise. Both restored.

**Also checked this round, and holding.** The certificate has 89 days left and
kamal-proxy renews it. The page's prose was read for doubled words, spacing
before punctuation and inconsistent compounds: `rate-limit readings` and `your
rate limit` are both correct English, one an adjective and one a noun. The
apostrophes are all typewriter ones — and so are the app's own, in its English
catalogue, so the page and the software agree and changing one alone would break
that. Two of the four findings were artefacts of the extractor, which replaced a
tag with a space and then reported a space before a comma.

**And one thing deliberately not changed.** The hero illustration leaves its left
two-thirds empty, which reads as a void before it reads as a desktop. That is
what a menu bar is: full width, with the status item 160 px from the right edge —
measured, in an entry above — and the window hanging from it. Every way of
filling that space makes the picture less true. The instinct was aesthetic and
had no proposal behind it that survived contact with what the picture is for.

## Shorter, three appearances, and something for a crawler to read

**Decision.** The copy is cut by a third, the page offers system/light/dark, and
the head carries structured data.

### The copy

1109 words to 753. Nothing was dropped that the page needed: the three-paragraph
sections became two, the six cells and seven facts kept every claim and lost the
second half of most sentences. The one paragraph removed outright was the hero's
third — "with one plan it answers a smaller question" — which broadened the
audience at the cost of blunting the opening.

Every phrase the guards hold the page to is still there, because those phrases
are the ones that quote the code: the intervals, the thresholds, the cache
lifetime, the language count. Shortening is not licence to stop being checkable.

### Three appearances

The page was dark only, and said so in a comment: "dark on purpose, not by
following the reader". It now offers the three the **app** offers — `Appearance`
is `system, light, dark`, and a page that let you pick a palette the app cannot
would be describing different software. A test ties the two together.

**How, and why it matters.** Every colour is a `light-dark(light, dark)` pair, so
there is one definition per colour rather than three copies of a palette. The
switch is three radio buttons and `html:has(#t-light:checked){color-scheme:light}`
— **no script**, which is the point: `default-src 'none'` is why nothing on this
page can run, and a theme toggle is not worth loosening it for. The trade is that
the choice does not survive a reload; the default is the reader's own setting, so
the two who have one are already served.

The light palette is not the dark one inverted. Severity doubles as a bar fill
and as a percentage, and `#34c759` on white is 2.3:1 — unreadable as text. The
light values are the darker greens, ambers and reds a white background needs,
measured the same way the dark ones were.

Two drawings had colours in presentation attributes, which cannot read a custom
property. Those moved to CSS rules; the attributes stay as what anything reading
the SVG without the stylesheet gets.

### SEO

`SoftwareApplication` structured data, `og:locale`, and a `theme-color` per
scheme. The question worth answering was whether `default-src 'none'` blocks a
`ld+json` block. It does not — it is data, not executed script — and this was
checked rather than reasoned: the live page was loaded with console logging on
and reports no violation, and the block parses as JSON.

### Verified

Both palettes rendered and read end to end. Widths still clear at 320 through
1024. Both halves of the new guard checked by breaking them — a missing light
control, and a script in place of the CSS switch.

**And a third file had to learn the same lesson.** `LandingQuotesTheCode` failed
on "once a minute", which the shortened copy had wrapped across two lines. It now
collapses whitespace before matching, as the README and preview guards already
do. Three separate guards have now been written with this bug in them; the next
one that reads a file for a phrase should start that way.

## The structured data offered software that cannot be had

**Decision.** The `SoftwareApplication` block no longer carries an `Offer`. A test
forbids one, and any `availability`, while the page says the app is in
development.

**Why.** The block added yesterday ended:

    "offers":{"@type":"Offer","price":"0","priceCurrency":"USD"}

An `Offer` states that the thing can be had, and price zero states it can be had
for nothing. It cannot be had at all: the repository is private, no release has
ever been published — the README says so, under a guard written for exactly that
reason — and two lines above in the same file the page says "in development".

This is the shape of defect this log is mostly made of, and it was introduced by
the hand that had spent the week removing them: a default stated as a rule, a
claim outrunning the software. It went in the one part of the page a person never
reads, which is why nothing caught it until the block was read back deliberately.
**The habit that found it was reading yesterday's work as though somebody else
had written it.**

**What replaced it.** Nothing. Schema.org has no honest way to say "not yet", and
an absent field claims nothing. The description now opens "In development." so
that what a crawler summarises matches what a reader is told.

**Also tied down.** The block names `macOS 14, iOS 17`, and `Package.swift` says
`.macOS(.v14), .iOS(.v17)`. Nothing else on the page states a version, so that
was the one figure with no second reader; the test now holds the two together.

**Verified.** The `Offer` was put back and the guard refused it. The live page
carries no `offers`. The appearance switch, added yesterday and only ever looked
at on a wide screen, was rendered at 320, 390 and 520 px: brand left, three
segments right, no wrap and no overlap at any of them.

## The mark followed the palette, and stopped being the icon

**Decision.** The four colours of the mark in the header are `icon.svg`'s own
literal values, not theme tokens. A test holds the two files together and refuses
a `var(--…)` in any of the four rules.

**Why.** When the page gained three palettes, every colour was tokenised — the
logo along with the rest. In the light palette the plate went from `#1c1c22` to a
pale grey, the inner ring from white to near-black, and the arc from `#34c759` to
the darker green the light palette uses for text contrast. Rendered beside
`icon.svg` the two are plainly different marks, and the browser tab was showing
the real one at the same time.

An icon is the one thing on a page that must not follow the page. It looks the
same on any wallpaper, in the Dock and in the tab; that is what makes it an icon
rather than a decoration. The arc in particular had a reason to be tokenised and
it was the wrong reason — `--accent` is darker in light mode because it carries
*text*, and the mark is not text.

**Two orphans went with it.** `--logo-bg` and `--hush` existed only to paint the
mark. A token nothing paints is a colour waiting to be used by mistake.

**Cost.** The mark is dark in a light page, which is exactly how an app icon
looks in a light window.

**Verified.** Rendered in both palettes beside `icon.svg`: identical in each. The
guard was checked from both ends — a theme token put back into the plate rule,
and a colour changed in `icon.svg` while the page was left alone.

**How it was found.** By asking what else the palette work had touched that
should not have been touched. The change was mine, from the day before, and it
had passed every existing check: nothing tied the drawing in the header to the
file in the tab.

## What else the palette work touched

**Decision.** Two checks and no changes: the preview's colours must come from the
page's dark palette or the mark, and the two colours left hardcoded were measured
rather than tokenised.

**The preview.** `og.png` is one image and cannot follow a reader's appearance —
it is the dark page, drawn once. Twelve of the thirteen colours in
`og-template.html` are exactly the page's dark values and the thirteenth is the
mark's plate, so the two agree today. Nothing was checking that they did. The
page's colours moved into `light-dark()` pairs the same week, and a dark value
adjusted on the way through would have left the preview holding the old one
without a word. The guard now reads the second half of every pair and requires
the template to paint only from those, plus `icon.svg`'s own.

**The two hardcoded colours, measured.** `.tag`'s background and `::selection`
are translucent fills stated once for both palettes, which looks like the same
oversight the logo turned out to be. Measured instead of assumed:

    badge      dark 5.52:1   light 4.82:1
    selection  dark 9.39:1   light 13.91:1

All above the 4.5 small text needs, so both stay. A translucent fill over a
themed background *is* themed — it takes the colour underneath. The logo was
different because it was opaque and because an icon should not follow anything.

**Verified.** The palette guard was checked from both ends — a dark value moved
in the page with the template untouched, and a stray colour introduced into the
template.

**On method.** This is the third iteration in a row spent re-reading the previous
one. Two of them found a defect; this one did not, and the checking is what makes
the difference between the two outcomes legible. The question that produced all
three was the same: what else did that change touch?

## The chart's colours were the app's, by coincidence as far as anything knew

**Decision.** `AccountPalette` stores its five colours as hex, the landing's
`--id-N` tokens must equal them, and the drawing must hand them out in the order
the app would.

**Why.** `AccountPalette.colour(for:among:)` takes an account's position in the
sorted list of ids. An id begins with its provider, `claude/` sorts before
`codex/`, so **Codex is coloured last however many Claude accounts there are**.
The landing's legend gives sam blue, sam.k violet and alex — the Codex one —
teal: exactly that rule, including the part nobody would reproduce by eye.

And the four identity colours matched the app's to the byte. They were decimal
triples in Swift and hex in CSS, written twice, agreeing perfectly, connected by
nothing. Either could have moved and the other would have sat there looking
right.

**One spelling now.** The palette is a list of `#rrggbb` and `colours` is derived
from it, because the page writes them that way and a test has to compare the two
lists. Reading hex here is no worse than reading `Color(red: 0.36, …)`, and it is
the same thing the CSS says.

**Three things the test holds.** Each `--id-N` the page defines equals
`AccountPalette.hexes[N-1]`. The legend's slots are the first few with no gap,
because the app hands them out by position and never skips. And Codex's slot
comes after every Claude one, which is the rule stated above rather than a
preference about colours.

**Verified.** All three by breaking them: Codex coloured before Claude, a palette
value moved in Swift with the page untouched, and a gap left in the legend's
slots.

**What this is an instance of.** The landing recreates the app's interface, and
every part of that recreation that is *derived* rather than chosen should be
derived from the same place. Row order was tied down long ago; bar widths last
week; the mark two days ago. Colour assignment was the last piece of the drawing
that agreed with the software by memory alone.

## Correction: the palette did not match "to the byte"

**What was written yesterday.** That the landing's four identity colours matched
`AccountPalette`'s "to the byte", and that moving the palette to hex was a change
of spelling only.

**What is true.** The decimals never sat on byte values at all. Each of the five
lands between two:

    blue    (91.80, 140.25, 216.75)   hex (92, 140, 217)
    violet  (140.25, 114.75, 204.00)  hex (140, 115, 204)
    teal    (76.50, 160.65, 173.40)   hex (77, 161, 174)
    mauve   (183.60, 114.75, 165.75)  hex (184, 115, 166)
    indigo  (107.10, 122.40, 183.60)  hex (107, 122, 184)

Four of the five hexes are the nearest byte to their decimal. The teal's blue
channel is not: 173.4 is nearer 173, and the page said 174. So the landing's teal
was a unit away from the app's, and adopting the hex as the source of truth moved
the **app's** teal by 0.6/255 rather than moving nothing.

**Why the claim was wrong, not just imprecise.** `Color(red:green:blue:)` holds
floating point and is converted when it is drawn; there was no byte on that side
to be identical to. Comparing a float against a hex and calling the result
"identical" is a category error, and it was made by converting one to the other
and not looking at the remainder.

**What stands.** The change itself: one spelling, and a value that is now exactly
what both draw. A 0.6/255 shift in one channel of one colour is beneath
perception and the test that compares the two lists is worth more than the
decimals were. But it is a change to what the app renders, and it was reported as
though it were not.

**The habit that caught it.** Re-reading the previous iteration's own claim with
the arithmetic in front of me instead of the memory of having checked it.

## The page's "not yet" list, and a lesson about probes

**Decision.** A test derives the unbuilt providers from `ProviderID.allCases`
minus the two that are implemented, and requires the page to name each — and to
name the two that work.

**Why.** The page says "Cursor, GitHub Copilot and Gemini CLI"; the app has
`ProviderID` with five cases and Settings lists three under "Later". The two
lists agreed by memory. A fourth planned provider would be added to the enum, and
the compiler would force it into every exhaustive switch — but not onto the page,
which would go on promising three.

**Also checked, and honest.** The Services pane shows toggles for Claude and
Codex and plain rows labelled "later" for the other three: no control that does
nothing, which was the thing worth looking for. The About pane reads its version
from the bundle rather than a literal, so that figure cannot drift either.

### The lesson, which cost more than the test

Verifying this guard by adding a sixth provider means editing an enum, which
breaks every exhaustive switch, which means a full package rebuild — minutes, not
the two seconds the suite normally takes. Three such probes were started before
that sank in, they stacked up on SwiftPM's build lock, and one `swift-test` sat
for twenty-two minutes holding it. Everything had to be killed and the tree
restored from git.

**The probe should cost what the assertion is worth.** The same guard has two
sides, and the other one — removing a name from the page — needs no rebuild at
all. It was run once, cleanly, and caught the omission. That is the same evidence
for a fraction of the time.

There is a second habit in here worth naming: each failed probe was launched
before the previous one had reported. Waiting for a result before ordering
another is not patience, it is what makes the result mean anything.

## One word doing two jobs, after the cut

**Decision.** The menu-bar cell says "whichever limit is closest to running out"
rather than "the window closest to exhaustion".

**Why.** Shortening that cell removed its subject. It had read "The icon carries
the window closest to exhaustion"; the cut left "The window closest to
exhaustion, and how long until it frees up", which opens a paragraph about the
menu bar with a noun this page uses for something else. "Window" appears three
times here and the other two mean the app's window — "the account row the window
uses", "with the window open". The app's own model calls a five-hour or weekly
period a `LimitWindow`, which is why the word was there; a reader has no reason
to know that, and "limit" is the word they already have from the rest of the
page.

The second sentence was rebuilt for the same reason: "Or the percentage, or both,
or just the icon" had depended on the removed subject too, and "just the icon"
reads oddly after a sentence that begins "The icon". It names the strip instead.

**No guard.** This is a judgment about prose, not a fact derived from the code.
Guards here exist for things that drift *from the software*; a page cannot drift
from its own vocabulary except by someone reading it, which is what happened.

**Also looked at.** The lower half of the page in the light palette, unseen since
the rewrite: the chart on a light panel, the six-cell grid's hairlines and the
facts list all hold. Nothing to change.

**How the ambiguity was found.** By reading the page end to end as a reader
rather than checking it as a set of claims. Every guard added this week would
have passed it — and did.

## Reading the README the way the landing was read

**Decision.** Six corrections to the README, and a test tying its account of the
deploy to what `deploy.sh` does.

**Why.** The landing has been read end to end, sentence by sentence, several
times. The README's *numbers* were guarded a few days ago — the sampling rule,
the retention, the section count — but nobody had read it as a newcomer would.
Doing that found six places where it had fallen behind:

- **"Plus a widget for the widget panel."** The opening line, clumsy and by now
  wrong: there are four widget sizes on the Mac, two shapes on a lock screen, a
  home-screen widget and a phone app.
- **"Its age is shown in the window."** Every surface shows it now. This is the
  same sentence that was corrected on the landing a week ago; the README was not
  looked at then.
- **"A break in a line is a stretch with the app not running."** One cause of a
  break, stated as the definition. And it omits what hiding an account does,
  which was fixed in the code precisely so a hidden account is *not* drawn as a
  break.
- **"## Widget"**, describing only the Mac.
- **"the Mac window, the widget and the phone"** — there are two widgets.
- **The deploy**, below.

**The deploy paragraph had rotted.** It said the script "asks the live URL for a
200 before reporting success", true when written and wrong for a week. The deploy
now compares every file by SHA-256, asserts `Cache-Control` on the URLs people
actually request, confirms the route reached `kamal-proxy`'s saved state and that
the container's restart policy is what the compose file says, and runs the width
check before shipping. Four checks were added one at a time, each with its own
entry here, and the sentence describing them never moved.

All nine claims in the replacement were checked against `deploy.sh` rather than
written from memory. A test now pairs each check with the words the README uses
for it, so removing either side fails.

**A guard that was about casing.** `theWidgetSizesAreTheOnesItDeclares` required
the literal "all four sizes"; the rewrite began a section with "All four sizes"
and it refused. The rule is that the README names four sizes, not that the phrase
sits mid-sentence — it matches case-insensitively now. That is the fourth guard
this week written against the shape of the text rather than the thing it means.

**What this says about the method.** Guards catch drift from code. They cannot
catch a sentence that was true and stopped being interesting, or a word that
means two things, or an opening line that undersells what was built. Only reading
does that, and the README had not been read since it was written.

## A typo translated faithfully into nine languages

**Decision.** Two corrections to the app's own words, and a test that no
catalogue writes a name in lower case unless it is the command.

**Why.** The English catalogue was read end to end, the way the landing and then
the README have been. Its numbers and its instructions had been audited several
times; the sentences themselves had not.

**"otherwise claude would be signed out."** In the Accounts pane, explaining what
"Active in CLI" means — three words after "Claude Code", written properly. It is
part of the key, so the tooling that keeps ten catalogues in step had copied it
ten times, and every translator had rendered the sentence around it faithfully:
`иначе claude разлогинится`, `sinon claude serait déconnecté`, `否则 claude 会被登出`.
One slip in English became ten.

**A caption without its full stop.** The empty window has two captions in the same
place: "Claude Code's credentials cannot be read, so the account signed in there
cannot be shown." and "Sign in to Claude Code or run Codex" — same position, same
role, one with a stop and one without. A person sees one or the other and should
not be able to tell that two hands wrote them. The stop was added in all ten,
each in its own punctuation: `।` for Bengali and Hindi, `。` for Chinese.

**The exception the guard has to allow.** "sign in via claude /login" is the
executable, and executables are lower case. So the rule is not "never lower case"
but "lower case only where a command's argument follows" — checked both ways: a
lower-case name in a Russian string is refused, and `claude /login` in the same
place is not.

**What this run is an instance of.** Three prose surfaces, read as a reader
rather than checked as claims: the landing found a word doing two jobs, the
README found six stale sentences, the catalogue found a typo multiplied by ten.
None of the thirty-odd guards in this repository would have found any of them,
because none of them was a disagreement with the code.

## Reading the other hundred strings

**Decision.** Three corrections in the Appearance and Accounts panes.

**"Theme" was a word from nowhere.** The pane is titled Appearance, the setting
is `Appearance`, the README says Appearance, the landing's switch says
Appearance, and macOS System Settings labels the same choice Appearance. One
picker said Theme — a word that appears nowhere else in this project or on the
platform. It says Appearance now, inside a pane of that name, which is exactly
what System Settings does. The `Theme` key is gone from all ten catalogues.

**A subtitle that had stopped covering its pane.** Appearance said "How the menu
bar icon looks and how account rows are laid out" — and the first control in it
is **Language**, which is neither, and is the most consequential thing there. It
now names all three: language, light or dark, and the look of the strip and the
rows.

**A subtitle with no subject.** Accounts read "Appear on their own when you sign
in via claude /login, or are added through the browser." — a sentence whose
subject is the heading above it. Every other pane's subtitle stands on its own:
"Where data comes from…", "How often to fetch data…", "What the app stores…".
This one now does too.

**And a full stop that had no siblings.** "No accounts yet." carried one; "No
accounts found" and "Nothing recorded yet", in the same role, do not. All three
are fragments, and fragments do not take one. Removed, in each language's own
punctuation.

**Two things checked and found sound.** "No data available" and "Something went
wrong." appear in no `loc("…")` call — they arrive through `Localization.shared`
and an extension on the same type, which the orphan guard scans and my grep did
not. Not orphans; a narrow search.

**The count so far.** Four prose surfaces read end to end this week — landing,
README, the app's long strings, the app's short ones — and each has produced
something. None of it was a disagreement with the code, which is the only thing
this repository's guards can see.

## The history was read the way an outsider would read it

**Decision.** Every identifier tying this repository to one person's machine,
Apple account, server or other projects was replaced across all 161 commits with
`git filter-repo`, and four new guards were added so the same classes cannot
return. The repository was private when this ran, which is the only reason a
rewrite was still cheap.

**What an audit of the whole history actually found.** All 913 blobs that have
ever existed here were dumped and scanned, not just the working tree. The good
news came first and is worth stating: no API key, no private key, no JWT, no
password, no URL carrying credentials, no agent trailer or session link in any of
the 161 commit messages, no EXIF or author metadata in any image, and no real
session fixture. The release workflow reads its certificate from GitHub secrets
and shreds the `.p12` in the step that used it. The OAuth `client_id` in
`OAuthEndpoints.swift` is Claude Code's own public client, which a PKCE flow
publishes by design — it is not a secret and was left alone.

**What it did find was smaller and more personal.** Five identifiers still lived
in tracked files: the name of the Mac this was written on, quoted from a failing
build (`Device "…" isn't registered`); the Apple team identifier, in the README
and five times in this log; the old bundle prefix, built from a personal domain,
1450 times; the previous directory name and the absolute worktree paths under it;
and a first name used as a non-ASCII test fixture. Six more had been removed from
the working tree but not from the history that still carried them: the full
signing identity — legal name and certificate — committed in `project.yml` for
three commits before it moved to the ignored local file; a real mail address in
this log; the deploy host's address, as `root@` and an IP, in three versions of
`site/deploy.sh`; a fixture address on a personal domain; the machine name again;
and the download URL from before the workflow rewrote it.

**Why the guard did not stop any of this.** `NoPersonalDataInTheRepository`
already refused mail addresses outside the reserved domains, account UUIDs,
credential shapes and `/Users/` paths — and it caught all of those. It had no
opinion about a machine name, a team identifier, a routable address, or a path
into a neighbouring project, so those walked past it. The four tests added here
close exactly those four gaps, and each was verified in both directions: a probe
file carrying one of each failed the right four tests, and passed once removed.

**Two of them ask the running system rather than storing an answer.** A denylist
of forbidden values would have to contain the values it forbids, which is the
problem restated. So the machine-name guard reads this host's name and login from
`ProcessInfo`, and the sibling-project guard derives the workspace from where the
checkout actually sits. Both travel to another machine and keep working there; a
written-down name would have guarded one stale string.

**What was deliberately left.** The GitHub account name stays: it is in the
repository's own URL and cannot be removed without moving the project to another
account. The commit author stays the author's own name and address on a domain
he owns, rather than the GitHub no-reply form — authorship is the one thing a
rewrite of this kind should not quietly take away, and the choice to keep it was
made explicitly rather than by default. Anyone cloning a public copy will read
that address in `git log`, which is the trade that was accepted.

**What it cost.** Every commit hash changed, so the remote had to be force-pushed
and any existing clone is now unrelated to it — the reason a bundle of the old
history was written to `../softcap-preclean-*.bundle` before anything ran. Two
filter-repo passes were needed rather than one: the first replaced the old
bundle prefix everywhere except inside the `sed` commands in a plan document,
where each dot is backslash-escaped and a literal rule therefore does not match
it. The second pass matched the escaped spelling. The guard file is
now exempt from its own scan, for the ordinary reason that a file naming
forbidden shapes contains every one of them; it is small, and it is the file a
reviewer should read most carefully.

## The hook would have approved every commit if the suite were renamed

**Decision.** `tools/hooks/pre-commit` refuses a run that examined nothing, not
only a run that failed.

**Why.** It ran `swift test --filter NoPersonalDataInTheRepository` and treated a
zero exit as "clean". A filter matching nothing is not an error to SwiftPM:

    $ swift test --filter ThisSuiteDoesNotExistAnywhere; echo $?
    ✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
    0

So renaming the suite, moving it to another file, or mistyping the string here
would leave a hook that approves every commit while looking exactly like a hook
that works — no error, no unusual output, a quarter of a second as always. It
guards the check whose two earlier failures put a mail address and an account
identifier into the history, and whose gaps cost a rewrite of all 161 commits
yesterday.

The hook now requires the summary line to report at least one test in at least
one suite, and says which filter matched nothing when it does not.

**Checked, and sound.** All eight guards in that suite do run under the hook's
filter, listed by name from its output rather than counted. Two of them derive
what they forbid from the running system — the host name and the login of
whatever machine is running — which reads like a gap until you notice where the
hook runs: on the machine doing the committing, which is the machine whose name
is at risk. That is why an environment-derived value is right here and a
written-down denylist would not be.

**And the hook refused this entry.** The paragraph above first quoted the two
values it was describing, to be concrete. That is the failure mode the hook
exists for, in the same shape as both earlier ones: prose describing a live run.
It was caught before the commit rather than by the next `make test`, which is the
whole point of moving the check here — and it is the only time in this log that a
guard has stopped the entry being written about it.

**A probe that proved nothing.** The first attempt renamed the suite to
`NoPersonalDataInTheRepo` and the hook passed, which looked like the fix failing.
`--filter` matches by pattern, and that name is a prefix of the real one, so the
suite ran normally. A name sharing no prefix produced the refusal. The lesson is
the one this log keeps recording: an instrument has to be wrong-able before its
agreement means anything.

## The blocker that had stopped being one

**Decision.** The stale widget registration was removed. The rename worktree is
now removable and was **not** removed — its state is another session's to judge.

**Why.** Every status report for a week has carried the same line: the rename
worktree cannot be deleted because it holds the widget's pluginkit registration.
Asking the system rather than repeating the sentence showed that is no longer
true, and had not been for some time:

    dev.example.StatusChecker.widget  →  /Users/…/old-project-directory/.claude/worktrees/…

The path does not exist. The project directory was renamed, and the registration
kept pointing at the old one — so it could not have been serving anything, and
removing the worktree could not have broken it. It also advertised the old
bundle prefix built from a personal domain, which the history rewrite had just
spent 1450 substitutions removing from the repository: the repository was clean
and the machine was still announcing it. `pluginkit -r` took it; the current
widget remains registered from the current checkout, and the app still writes its
snapshot to the shared container.

**What the worktree actually holds, since the report kept guessing.** Its branch
is fully merged — no commit in it is missing from `main`. It is 1.2 GB. It is 83
files behind `main`, and it carries nine staged changes on top of that old state,
64 lines substituted one for one. Nothing about it looks like work anyone intends
to resume.

That is not the same as knowing, and 1.2 GB of parked state is not this session's
to discard while another session is working in the same repository. What was
blocking it is gone; what it contains is for whoever parked it.

**Also verified after the history rewrite.** 1450 substitutions across every
commit deserve more than a grep: both platforms build, all 334 tests pass, the
bundle identifiers and the app group are intact, and the running app writes to
the shared container the widget reads. Checked end to end rather than inferred
from a clean `git status`.

**The habit.** A blocker repeated in every report is a claim like any other, and
it had gone stale while being restated. It cost one command to find out.

## The documented first step did not work

**Decision.** The README says what a fresh checkout actually does, having been
tried on one.

**Why.** CI has never run — GitHub Actions has been stopped on billing since
before the first push, verified again today rather than repeated — so nothing has
ever built this project anywhere but the machine it was written on. A clone was
made into a scratch directory and the three documented commands were run.

    make test       334 tests pass
    make build-ios  BUILD SUCCEEDED
    make build      BUILD FAILED — "requires a provisioning profile"

The README promised the opposite of the third: "Without it the build is signed
ad-hoc, and macOS will ask for your keychain password on every rebuild." It does
not build at all. The iOS targets set `CODE_SIGN_IDENTITY: "-"` in `project.yml`
and the Mac ones never did, so the sentence described the iOS behaviour as though
it covered everything — invisible here, where `Signing.local.xcconfig` exists.

**The cause is Apple's, not the project's.** Giving the Mac targets the same
ad-hoc identity was tried in the clone and changed nothing: the App Group
entitlement is what demands a profile, and macOS will not sign an App Group
without a development team. So there is no default that makes `make build` work
for a stranger, and the honest thing is to say so.

**There is a way past it, and it was already in the repository.** The release
workflow builds with `CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`, which
skips signing rather than failing it. Tried in the clone: BUILD SUCCEEDED, and
`Softcap.app` is produced. Entitlements are not honoured without a signature, so
the App Group is unavailable and the widget has nothing to read — which is the
trade, and the README now names it.

`make build` was left alone rather than made to fall back. A silently unsigned
build is one whose widget silently has no data, and that is a worse thing to hand
someone than an error naming what is missing.

**The suite is portable, which was the other question.** All 334 tests pass in the
clone, and three of them were made to fail there on purpose — the landing's
numbers, a catalogue's percent sign, a personal address in a new file — because a
guard that examines nothing passes too. That lesson is one entry old.

## The hook was tried the way a stranger would try it

**Decision.** The README names all eight checks the commit hook runs, and a test
holds the count and the suite's name against the hook's filter.

**Why.** Yesterday's clean clone showed the documented build did not work.
The same question, asked of the other documented first step: does
`tools/install-hooks.sh` work on a checkout that has never had it, and does the
hook then stop anything?

A fresh clone, the installer, and a file carrying the deploy host's address:

    $ tools/install-hooks.sh
    hooks: tools/hooks
    $ git commit -m probe
    commit refused: personal data in the working tree
    ✘ noAddressesOfRealHosts() — offenders: ["hostprobe.md: <the address>"]

It works, end to end, in a checkout that has never run it. And the check that
caught it is one of four the README did not mention.

**What the README said.** That the hook refuses "a real mail address, an account
identifier, anything shaped like a token, or a home path" — four things, written
when there were four. There are eight. The four it omitted are the machine's own
name, a path into a neighbouring checkout, a routable host address and the Apple
team identifier: precisely the four added after a rewrite of all 161 commits
found what the first four had no opinion about, which makes them the four most
worth naming.

**Two things the test now holds.** The count, so a ninth check cannot be added
without the sentence following it. And the suite's name in the hook's filter
against the name in the file, since a filter matching nothing exits zero — the
defect found two entries ago, now guarded from the other side as well.

**A measurement error worth naming, again.** The probe printed "commit exit code:
0" after piping through `head`, which reports the pipe's last command. The commit
had plainly failed — the branch tip had not moved. Same trap as the Makefile's
missing `pipefail` and the width check's exit status: `$?` after a pipeline is
not the thing you asked about.

## The last documented tool, and the gap inside it

**Decision.** `tools/add_strings.py` refuses a key that is missing a language
rather than filling it with the English text.

**Why.** It is the last documented command nobody had run in these sessions, so it
was run: a key with all nine translations went into all ten catalogues, English
got the key itself, and a second run added nothing. Everything the docstring
promises, verified.

The gap was one line inside it. `translations.get(lang, key)` meant a language
left out of the input was filled with the English key — silently. The catalogues
would stay the same size, every key would line up, no orphan would appear, and
**nine languages would show English while every guard in this repository was
satisfied**. Nothing downstream can tell that from a word that is genuinely the
same in both, which is why it has to be refused at the only place that knows.

Supplying the English text explicitly is still allowed. That is the caller saying
so, which is a different act from forgetting.

**The catalogues were audited for it first, and are clean.** Every value equal to
its English key was listed: three languages share `%lld s` and `%lld min`, which
are the SI abbreviations and correct in French, Spanish and Portuguese. Nothing
else. So the hazard had never fired — this closes it before it does rather than
after.

**What this run is the end of.** Every command the README tells a person to run
has now been run the way that person would run it. Two were broken — `make build`
on a fresh clone, and `make run-ios` before that — one was described wrongly, and
this one worked but could quietly produce a catalogue that looks translated and
is not.

## The response nobody had looked at

**Decision.** A path that does not exist gets the security headers, no `Server`
header, and a sentence instead of nothing. `deploy.sh` checks all four on every
deploy.

**Why.** Every check written for this site asks about files that are there. The
digests compare what was shipped; the header check reads `/` and the three
assets. Nobody had asked what a wrong URL returns, and it was:

    HTTP/2 404
    server: Caddy
    content-length: 0

No Content-Security-Policy, no nosniff, no X-Frame-Options, no Referrer-Policy —
and `Server: Caddy` announced, four lines below a `-Server` in the same file that
was written to prevent exactly that. The `header` block never reaches a response
`file_server` produces by *not* finding a file.

This is the same defect as the caching rule that was written for `/index.html`
while everybody arrives at `/`: a directive that is correct about the paths it
names and silent about the one it does not. Twice now, in the same file. The
common thread is that both were verified by asking a URL that works.

**And the body.** A reader who mistypes got a blank page — not a styled 404, not
even Caddy's own "404 page not found", nothing. It now says what happened and why
there is nowhere else to go: this site has one page.

**What is repeated and why.** `handle_errors` is a route of its own, so the
headers are written again inside it. Only four: `Permissions-Policy` governs
features a body with no content cannot use, and `img-src`/`style-src` have
nothing to permit. The duplication is real and the alternative — one block
covering both — is not something Caddy offers here.

**Verified by removing it.** With `handle_errors` taken out and shipped, the
deploy failed with five separate complaints and exited 1. Restored, all five
pass. The site was left serving the good version.

## One sentence for four different things in the sign-in

**Decision.** Each outcome of a browser return gets its own message.
`"Could not read the browser response"` is gone.

**Why.** It stood at three places covering four situations, and `OAuthCallback`
already names all four precisely:

- `.denied` — the person pressed Deny. The reply was read perfectly and it said
  no. Telling them the app could not read it is simply false.
- `.stateMismatch` — a reply that does not match the request that was sent.
- `.unrelated` — on the paste path, text that is not a code at all: much the most
  likely thing to happen when somebody pastes by hand.
- and a fourth that is not about the browser at all — the app having lost its own
  PKCE verifier, so there is nothing to exchange the code against. That one sent
  the reader looking at their browser for a fault in the app.

They now say: *Sign-in was declined.* / *That reply belongs to a different
sign-in. Start again.* / *That is not the code from the page.* / *The sign-in lost
its place. Start again.* Four keys in ten languages, added with
`tools/add_strings.py`, which refuses a missing language as of this morning — the
first real use of that.

**What was checked and left alone.** The listener treats `.unrelated` as a stray
request and keeps waiting, with a comment naming a favicon fetch as the case. A
first reading of the greps suggested it aborted the sign-in; reading the lines
above the guard showed the case handled correctly, before anything was changed.

**The orphan that followed.** Removing the last use of a key leaves it in ten
catalogues with nothing pointing at it, and `NoOrphanStrings` said so on the next
run. Removed from all ten.

## The page's central promise, checked against the running app

**Decision.** No change. Recorded because the check had never been made and
because a live failure was traced rather than assumed.

**The promise.** The page says Softcap shows every plan at once — "what is spent,
what resets when, which account to open next". The last clause is an ordering
claim, and a test has held the *mock* to it for weeks: least loaded first, errors
at the bottom. Nobody had asked what the running app does.

    codex    peak   0
    claude   peak  73
    claude   peak   —  (failed)
    claude   peak   —  (failed)

Ascending, failures last. The promise holds where it matters.

**The two failures, traced.** `needsLogin` — "no usable refresh token; sign in
again". Three explanations were considered and two ruled out by looking rather
than reasoning. The history rewrite replaced the old bundle prefix 1450 times and
could have taken the keychain service with it: `CredentialStore.ownService` is
still `StatusChecker-accounts`, kept deliberately through the rename, and the item
is still in the keychain under that name. Nothing changed here today touches
credentials either.

What remains is the documented trade: the app keeps a copy of an inactive
account's refresh token, and signing into that account again with `/login`
rotates the token server-side, which invalidates the copy. The app drops a
rejected token rather than re-sending it — an entry of its own — and says
**Sign-in required** in the row, with the raw diagnostic left in the log where a
person is not made to read it. Working as designed, and two accounts on this
machine want signing into again.

**Not done, and why.** `og.png` is 132 KB against a 10 KB compressed page, and no
PNG optimiser is installed. It is fetched by link scrapers and cached for a week,
so the weight costs no reader anything; hand-rolling a quantiser to save 90 KB
nobody waits for is work with a wrong shape.

## A deploy that hangs is worse than one that fails

**Decision.** Every `ssh` in `deploy.sh` carries `ConnectTimeout=10`, `rsync` is
told to use the same, and one reachability check runs before any work.

**Why.** The script is run unattended, every twenty minutes, by a loop. Its curl
calls have had `--max-time 20` from the start; its ssh calls had `BatchMode=yes`
— which stops it waiting for a password — and no timeout at all.

Measured rather than assumed: one ssh to an unroutable address takes **75
seconds** to give up. There are six ssh calls and two rsync transfers. A host
that is simply switched off would have stalled this script for most of ten
minutes, saying nothing until the end, inside a twenty-minute interval.

Now it is ten seconds and one sentence:

    198.51.100.1 does not answer on ssh — nothing was built, copied or deployed

The check is placed before the images are rebuilt and before the width check, so
a dead host costs nothing but the ten seconds — and the message says so, because
"deploy failed" leaves a reader wondering what got half-done.

**Cost.** A connect that legitimately takes longer than ten seconds now fails.
The host is a droplet on a well-connected network and an ordinary deploy takes
23 seconds end to end for thirteen checks; if that ever changes, the number is
one place.

**Tested both ways.** Against an unroutable address in the reserved
documentation range: ten seconds, exit 1, nothing touched. Against the real host:
thirteen checks pass and the live page still matches the repository.

## The range had a top and nobody had looked above it

**Decision.** `check-widths.sh` runs at 1440 and 1920 as well.

**Why.** The check was written for the failure it was built to catch — a page
scrolling sideways on a phone — and stopped at 1024. The page was rendered at
1920 and read: content centred in the 980px wrap, the mock intact, the appearance
switch on the wrap's right edge, nothing stretched. Nothing to fix.

But "nothing to fix at a width nobody checks" is the state every defect in this
log was in before it was found, and two more widths cost about two seconds. A
failure up there would need an element wider than the window, which is
unlikely — and unlikely is not the same as tested.

**Cost.** Two seconds per deploy, and one number in the README that now says
320–1920 rather than 320–1024.

## The README sent people to a note that was not there

**Decision.** The note exists, `docs/superpowers/plans/README.md`, and a test
requires every path the README points at to be present.

**Why.** The README said of the plans directory: "mostly Russian; historical,
already carried out — **see the note there**". There was no note — not a file,
not a heading at the top of a plan. A reader who followed that instruction found
three documents totalling 7,500 lines, opening with a banner addressed to a tool:
*"REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development…"*. Nothing said
what they were or that they were finished.

**And "mostly Russian" was wrong too.** The newest plan is entirely English; the
two older ones are 14% and 17% Cyrillic by line. Both facts were counted, not
recalled.

The note now says what each plan built, that the banner is not addressed to the
reader, why two of them have Russian in places, and — the part worth having —
that `DECISIONS.md` is the current record and a plan is what was *going* to
happen.

**The guard is about references, not this one file.** Eleven paths the README
names are checked for existence: the log, the specs, the plans and their note,
the mock-ups, and the five scripts it tells people to run. A broken reference in
the first document anybody reads costs more than most defects in this log.

**Two environment traps in one iteration, both already known.** Restoring the
quarantined note failed because `ls` here is aliased to long format, so a
`$(ls -t …)` captured a listing line rather than a path — the same shape as
`GREP_OPTIONS=--color=always` turning a captured UDID into escape codes. The file
came back with its path written out. Neither is this repository's to fix; both
are worth recognising on sight.

## The rename missed a space

**Decision.** The window mock-up says Softcap, the README says what both mock-ups
are, and a test refuses either spelling of the old name in anything a reader
opens.

**Why.** `docs/design/menu-window-variants.html` was headed **"Status Checker —
три компоновки одного окна"**. The rename replaced `StatusChecker` everywhere and
this is `Status Checker`, with a space, so every sweep since — including three of
mine — went straight past it. Its neighbour, `settings-screen.html`, was renamed
correctly, which is why nothing looked odd.

**The exception, and it is real.** `StatusChecker-accounts` is the keychain
service, kept through the rename so that nothing already stored is lost. The test
strips that string before looking, so the name survives exactly where it must.

**What the guard covers, and what it deliberately does not.** The two mock-ups,
the landing, the preview template and the README — the things a person opens. Not
the decision log and not the plans: those are a record of a time when the name
*was* the old one, and correcting them would falsify the record rather than
tidy it.

**The mock-ups needed a sentence more than a rename.** They are in Russian, made
before the app existed. The settings one draws seven panes and they are not the
app's seven: it has a hot-key pane and no statistics screen, because statistics
were added later and the hot keys ended up inside other panes. The README called
them "window and settings mock-ups" and left a reader to discover that. It now
says what they are and where they are out of date — the same gap as the plans
directory, one entry ago, and found by the same question: what does somebody
following this instruction actually find?

**Also exercised.** `site/make-favicon.sh`, the last documented script never run
in these sessions: it rebuilds the icon byte-for-byte identical to the committed
one. Every script the README names has now been run.

## Correction: an entry about the rewrite put back what the rewrite removed

**What happened.** The entry "The blocker that had stopped being one" quoted the
stale widget registration verbatim, to be concrete about what was found. That
quotation carried the old bundle prefix — built from a personal domain, the
identifier `git filter-repo` had replaced 1450 times a few hours earlier — and
the old project directory name, straight back into the file the rewrite had just
cleaned.

The line now reads as the rest of the log does, with `dev.example.…` and a
described directory. The redaction is in the working tree; the commit that
introduced it still carries the string, and removing that needs another
`filter-repo` pass, which is the owner's to run.

**Why nothing stopped it.** The nine — then eight — checks in
`NoPersonalDataInTheRepository` cover a mail address, an account identifier, a
credential shape, an absolute path, this machine's name and login, a sibling
checkout, a routable host, and the team identifier. None of them had an opinion
about a bundle identifier. **The rewrite cleaned the past and nothing was
watching the present**, and the first thing to walk through the open door was an
entry celebrating the rewrite.

**The ninth check.** A bundle identifier for this project begins with
`app.softcap`, optionally behind `group.`; `dev.example` is allowed because that
is the placeholder the rewrite itself left behind. Stated as a shape, so this
file does not contain the value it forbids — the same reasoning that made two
earlier checks ask the running system rather than store an answer.

**Found by taking the previous entry's lesson seriously.** "Status Checker" hid
behind a space. The question that followed — what other spellings have the sweeps
been missing? — was asked of the personal identifiers rather than the product
name, and this is what it returned. One grep.

**And the count guard earned itself.** Adding a ninth check made
`theReadmeCountsTheChecksTheHookRuns` fail, one day after it was written for
exactly that. The README says nine now, and names the new one.

## The longest sentence, and the guard that objected to a capital letter

**Decision.** "Cost of running it" is two sentences, and the landing's checks
match without regard to case.

**Why.** Read sentence by sentence, the page has one that is genuinely hard: 37
words carrying three alternatives in a row — a request per account per poll, five
minutes apart, once a minute, or anywhere between thirty seconds and an hour. It
is now the count, then the intervals.

Splitting it moved "five minutes apart" to the start of a sentence, and
`thePollIntervalsAreTheOnesThePageNames` refused the capital F. That is the
**third** time a check in this repository has been written against the shape of
the text instead of the thing it means: the README's "all four sizes" began a
section and was refused two days ago, and the landing's "once a minute" straddled
a line break before that. All eight phrase checks on the landing now match
case-insensitively, and the comment says why so the fourth one is not written the
same way.

**Also asked, and already answered.** Following the previous entry's question —
what else can be written that the checks do not know? — the server paths were
next: `/opt/<name>` naming a neighbour on the shared host. `noPathsIntoOtherProjects`
already covers it, allowing this project's own directory and the placeholder, and
it refuses a made-up neighbour when one is written. The author of that check
thought of it first.

## Prose is asked one way and code another

**Decision.** A `says` helper matches a phrase without regard to case, and the
eleven checks that read something a person wrote now use it. Checks that read
code keep `contains`.

**Why.** The same defect has been found three times in four days, each time
looking like a one-off:

- "once a minute" straddled a line break when the copy was shortened;
- "all four sizes" began a section after a rewrite and the README guard refused
  the capital A;
- "five minutes apart" took a capital F yesterday when a long sentence was split.

Every time the rule was *the document says this* and the check was *the document
says this, in these letters, on this line*. Fixing the third one on its own would
have left the fourth to be found the same way.

**The distinction is the point, not the leniency.** `contains` stays wherever a
check reads code — `.package(` in a manifest, `layoutDirection, loc.layoutDirection`
in a view, `struct NoPersonalDataInTheRepository` against the hook's filter. A
capital letter there is a different thing, not the same thing rephrased, and the
suite-name check was verified to still refuse a renamed suite.

**What each call now states.** `says` means prose; `contains` means code. The
helper carries the three failures in its comment, so the next person writing one
of these reads why before choosing.

**Verified both directions.** The README's "Seven sections" and "ten languages"
were shouted and title-cased: no complaint. "Seven sections" was changed to "Six
sections": refused. The suite name was lower-cased: refused.

## Nine checks that would have passed without reading a file

**Decision.** Every walk that feeds a guard refuses to return an implausibly
small list. Four walks, four floors.

**Why.** Two days ago the commit hook was found to treat a
`swift test --filter` that matched no suite as success. The same question, asked
one layer further in: what if the *suite* runs but its file walk comes back
empty?

`textFiles()` was made to return `[]`. **All 338 tests passed.** The nine checks
that protect against personal data — whose gaps cost a rewrite of 161 commits —
each walked an empty list, found no offenders, and reported success. The
pre-commit hook runs exactly that suite, so it would have approved anything while
looking, again, like a hook that works.

Nothing had to break for this: a moved directory, a `#filePath` resolving
differently in another build layout, a skip-list with one entry too many. The
scan is anchored to `#filePath`, which is a compile-time constant — it is not
fragile today, and it does not have to be fragile to be worth a floor.

**Where the floor goes.** In the walk, not in each caller. Nine tests share
`textFiles()`; a floor in each of them is nine chances to forget. The other three
walks — Core's sources, the ten catalogues, the two widget directories — have one
each.

**The numbers are honest rather than tight.** Fifty files against roughly a
hundred and seventy, ten catalogues, ten Core sources, two widget directories.
Far below any real count and far above zero, so an ordinary addition never trips
them and a total failure always does.

**Verified, four times.** Each walk was made to return `[]` in turn: every one
now fails the checks that read it, naming what was scanned and how little it
found.

**This is the second instance of one idea.** A check that examines nothing
passes. It was true of the hook's filter and true of the walks beneath it, and
both times the thing looked healthy from outside. Where else it is true is worth
asking again.

## The same idea, third and fourth time

**Decision.** `check-widths.sh` refuses an empty width list and requires every
frame it asked for to have reported. `deploy.sh` refuses a served-file list
shorter than five, before anything is copied or deleted.

**Why.** A check that examines nothing passes. Found in the commit hook's
`--filter`, then in the file walks beneath it. Asked of the two scripts:

**The width check.** With `WIDTHS` empty it renders no frames, finds no
overflow, prints `all clear` and exits 0 — measured, not reasoned. The deploy
reads that line and ships. It now refuses an empty list, and the page it builds
compares the number of frames that reported against the number asked for, so a
frame that fails to load is a failure rather than a silence.

**The deploy's file list, which is worse.** `SERVED` decides what is copied, what
`--delete` removes from the server, and what is verified afterwards. Empty, the
verification loop finds no fault and reports success. But `rsync -az --delete`
with no sources would also be left holding a single argument — the live site's
directory. That is not a vacuous pass, it is a hazard, and it is why this one was
**not** tested against the real host. Reasoned about, prevented at the top of the
script, and then checked with a list of one, which is refused before rsync is
reached.

**On not running the experiment.** Every other floor in these two entries was
proved by breaking the thing and watching it fail. This one was not, because the
failure being demonstrated would have been a `--delete` pointed at the live
site's files. Naming that distinction matters more than the tidiness of having
tested all four the same way.

## A promise about a file nobody opens

**Decision.** A test reads `favicon.ico`'s own directory and requires it to hold
exactly the sizes the page declares.

**Why.** The page says `sizes="16x16 32x32 48x48"`. That is a statement about a
binary produced by a script and never looked at by a person. The sizes are
written by hand twice — once in `make-favicon.sh`, once in the page — and nothing
joined them. A browser asked for a size the file does not hold does not complain;
it takes whichever it finds. The only way that is ever noticed is by somebody
opening the file, and there is no reason for anybody to.

They agree today: three images, 16, 32 and 48, and the page names those three.
Checked by reading the six-byte header and the sixteen-byte entry per image
rather than by trusting the script's own summary line.

**Verified from both ends.** The page was made to declare a fourth size: refused.
The script was made to render and pack a fourth: refused. The icon was restored
and its digest still matches the one being served.

**Where the "examines nothing" question ends, for now.** Asked of the favicon
builder too: its sizes are literals in the file and a missing render throws when
the packer reads it, so an empty run fails loudly. Four places had the defect and
are fixed; this one did not.

## Two more promises about things nobody looks at

**Decision.** The suite that held the icon to its declaration now holds two more:
the preview's dimensions and the colour a browser paints around the page.

**Why.** Yesterday's find was a statement in the head about a binary nobody
opens. The question that follows is what else in the head is written twice with
nothing joining the halves. Two things:

- **`og:image:width` and `og:image:height`.** A scraper trusts the numbers, lays
  out a card of that shape, and draws whatever arrives into it. The PNG is
  rendered by a script; the numbers are typed. Read from the IHDR chunk rather
  than from the script's intent: 1200×630, and the head says 1200×630.
- **`theme-color`, twice, one per scheme.** It is the page's own background,
  stated again for the window furniture. Against the two halves of `--ink`:
  `#fbfbfd` and `#0e0e12`, matching.

Both agreed already. Neither was checked, and both are invisible when wrong — a
card cropped a little oddly on somebody else's timeline, a strip of chrome half a
shade off the page in a screenshot nobody takes.

**Verified from the side that would drift.** The declared height was changed to
628 and refused; the dark background was moved one step and the theme-color left
alone, and refused.

**The shape of these three finds.** A fact stated twice, in two languages —
markup and binary, markup and stylesheet — with the second copy invisible. The
guard is always the same: read the thing itself, not the intent of the script
that made it.

## The site says who it is six times

**Decision.** One test requires every copy to agree: the address, the name, the
preview and the description.

**Why.** Counted rather than assumed. The address appears five times in the
files — `canonical`, `og:url`, the structured data, the sitemap's `<loc>`, the
line in `robots.txt` — and a sixth as the domain `deploy.sh` ships to. The name
appears five times, the preview three, the description twice. Every copy agrees
today and nothing joined any of them.

The failure this prevents is a quiet one. A `canonical` left pointing at an
address the site no longer answers on costs whatever search traffic there was and
shows no symptom on the page: it renders, it deploys, every digest matches. The
only reader who notices is a crawler, months later.

**The rule is agreement, not particular values.** The canonical's origin is taken
as the truth and the other five are held to it, so the domain is free to change
in one edit and the test says which copies were missed. The name works the same
way from `og:site_name`, and `<title>` has to begin with it.

**Verified three ways.** One `og:url` moved to another domain: refused. The
sitemap line in `robots.txt` left on an old host: refused. `twitter:title`
lengthened by a word: refused.

**The same shape, fourth day running.** A fact written more than once with
nothing joining the copies — the icon's sizes, the preview's dimensions, the
chrome colour, and now the site's own identity. The tell each time is that the
second copy is somewhere a person never looks.

## Five files name the app group

**Decision.** A test requires all four entitlements files to name the group the
code goes looking for, with the team prefix exactly where the platform needs it.

**Why.** The same shape as the site's identity, in the app. The group is written
five times: four entitlements files and one constant in `SharedSnapshot`. macOS
takes `$(TeamIdentifierPrefix)` in front, iOS must not have it, and the code asks
the running binary which group it was actually granted and picks the one ending
in its own constant.

That last part is well made — the code cannot drift from what the binary holds.
It can drift from the **files**. Change an entitlement without the constant and
the lookup matches nothing, falls back to the constant, and asks for a container
the binary was never granted: `containerURL` returns nil, nothing is written, and
the widget shows "No accounts found". On iOS the constant is used directly and
the mismatch is immediate.

**There is no error anywhere in either case.** The app runs, polls, and appears
healthy. The widget looks like one nobody has configured. That is the whole
symptom.

**Verified twice, and the running app checked after.** The iOS group was renamed
away from the constant: refused. The team prefix was taken off the macOS group:
refused. Restored, both builds clean, and the live app still writes its snapshot
into the group container the widget reads.

**Fifth day of one idea.** A fact written more than once with nothing joining the
copies. It has now been closed for the icon's sizes, the preview's dimensions,
the chrome colour, the site's identity across six files, and the app group across
five. The tell is unchanged: the second copy lives somewhere no one looks, and
the failure it causes has no error attached to it.

## What the chart actually has to draw

**Decision.** Nothing changed. Recorded because the feature was described in two
documents and never looked at against real data, and because the rename left
something behind on disk that is the owner's to decide about.

**What the data says.** 462 readings, 236 of them weekly, spanning 28 July to 1
September — 34 days against a 35-day retention, so the oldest are about to be
pruned on schedule. Per account:

    codex    121 readings   23 segments   34.6 days
    claude    58 readings    1 segment     1.1 days
    claude    33 readings    1 segment     0.8 days
    claude    24 readings    2 segments    0.8 days

That asymmetry is the documented one, seen for the first time: Codex reaches back
a month because its readings are imported from the files the CLI has been writing
all along, and Claude begins the day the app first ran, because its API answers
for the present only. The README says exactly that; this is what it looks like.

**Twenty-three segments for Codex, against one break in the illustration.** The
mock draws a single gap and reality has twenty-two more, because a Mac sleeps.
The illustration is not claiming to be this machine — its whole point is to show
what a break means, and one is enough to say it. Left alone deliberately rather
than by not noticing.

**The rename left a container behind.** `group.dev.<domain>.StatusChecker` still
exists beside the current one: 20 KB, last written the day of the rename, holding
a history, a snapshot and a metadata file. Its Codex readings are all in the new
history — they are re-imported from the CLI's own files on every launch — so what
exists only there is **nine Claude readings from 31 August**, and three Codex ones
that fell outside the thinning rule.

Not touched. It is the owner's data, and unlike the stale widget registration
removed a few days ago it is not inert: it is a small, real, unrecoverable piece
of one afternoon's history. Worth knowing about because the directory is named
after the identifier the history rewrite spent 1450 substitutions removing from
the repository, and it is still on this disk.

**A hypothesis that was wrong, and how.** The Claude lines being a day long
looked like the rename having orphaned weeks of history. Reading the old
container showed it never held more than nine Claude readings: the app had only
been recording Claude for a day before the rename either. The symptom was real
and the explanation was not.

## The store that runs had no tests

**Decision.** `UsageHistoryStore` has four, covering what it does that
`UsageHistory` does not.

**Why.** Yesterday's look at the real data showed thirty-four days of history
against a thirty-five day ceiling: the oldest reading is about a day from being
dropped, by a path that has never run on this machine. That was worth checking
before it happens.

`prune` is called — twice, on record and on merge — and `UsageHistory` has a test
for it. But every test in that file exercises the value type. **Take the prune
line out of `UsageHistoryStore.record` and all of them still pass**, while the
file on disk grows for ever. The store is what runs, and it had no tests at all.

**Four, for the things only the store does.**

- Recording drops what has aged out, measured against the real `retention`
  rather than an arbitrary cutoff.
- A reading sitting exactly on the cutoff is kept — `removeAll { $0.at < cutoff }`
  and a month of history hanging off a strict comparison, which is the kind of
  thing a rewrite flips without meaning to.
- A poll that adds nothing does not rewrite the file. The app polls as often as
  once a minute and the thinning rule rejects most of those; without the guard it
  would rewrite a month of readings all day for no change.
- What was written comes back.

**Verified by removing each.** The prune line taken out: the aged-reading test
fails. The `guard history != before` taken out: the file's modification date
moves for a poll that added nothing, and the test says so.

## The one number a person looks at all day

**Decision.** `menuBarSummary` has tests.

**Why.** Yesterday's find — the store that runs having no tests — suggested a
question rather than an answer: what else runs untested? Every public type in
`Core` was checked against every test file. Most of what came back is views or
wrappers around the system, which are not unit-testable and are honest about it.
One was neither.

`menuBarSummary` decides the single figure and the single countdown a person sees
without opening anything. Three modes, and a deliberate choice inside it that the
comment argues for and nothing enforced: **the busiest window, not the soonest to
reset** — a free account's reset is always the soonest and says nothing about
where to go and work.

**Six tests, for what the strip promises.** That the busiest window wins and the
countdown belongs to *that* window. That each account offers its own peak, so a
quiet account with one hot limit still surfaces. That asking for the five-hour or
the weekly ignores the other. That an account which failed carries no windows and
must not silence the ones still answering — the state this machine is in right
now, with two accounts wanting a sign-in. That nothing to show is nothing. And
that the colour comes from the window that was chosen, so the strip and the row
agree about how bad it is.

**Verified by changing the rule.** Swapping "busiest" for "soonest to reset" fails
five of them. Making a failed account count as zero per cent fails the two that
say an empty strip means an empty strip.

## Adding one setting would have reset everybody's settings

**Decision.** `Preferences` decodes field by field, each falling back to its own
default. A missing field, or one of the wrong type, costs that field and nothing
else.

**Why.** Following the same question as the last two entries — what runs
untested, and what fails without an error — into the settings. The synthesised
`Codable` refuses a blob missing any one of the sixteen non-optional fields, and
`PreferencesStore.load()` answers a refusal with `.defaults`. Proved by encoding
the defaults, removing one key, and decoding: nil.

So **adding a twenty-second setting would silently discard the twenty-one already
chosen** — the language, the appearance, the thresholds, the quiet hours, the
hidden accounts, both hot keys, the Codex root — on first launch after the
upgrade, with nothing in the log and nothing on screen. The person would find the
app in English with default thresholds and no way to know why.

`SharedSnapshot` met this a week ago and answered it by making one new field
optional. That fixed the next addition. This is the same lesson made general: it
fixes all of them.

**A test was pinning the old behaviour.** `partialDataFallsBackToDefaults`
asserted that `{"appearance":"dark"}` yields *every* default, on the grounds that
not crashing mattered more. Both are available. It now says the setting that was
there is kept and the rest take theirs — the fourth time in this log a test has
held a lesser behaviour in place by describing it faithfully.

**Three tests, and one of them is the point.** Partial data keeps what it has; a
malformed field costs one field rather than twenty-one; and every field
round-trips through save and load, so a hand-written decoder cannot quietly drop
one. That last is what a per-field decoder needs and a synthesised one never did.

**Verified three ways.** The synthesised decoder put back: three tests fail. One
field dropped from the hand-written one: the round-trip test names it. The live
app relaunched: it reads its settings and keeps writing snapshots.

## An unreadable account list must not be written over

**Decision.** `CredentialStore` remembers that the keychain item held something
it could not decode, and refuses to write while that is true.

**Why.** Yesterday's settings find asked what else is persisted through a
synthesised `Codable`. Four things are: the shared snapshot, the history, the
history's samples, and the account list. The last has the worst consequence and a
path that makes it permanent.

`load()` answered a decode failure by returning early, leaving `accounts` empty.
Nothing distinguished that from *there is nothing stored yet* — and the next edit
would encode the empty list and write it into the item. **The item is the only
copy of the refresh token for every account not currently active in the CLI.** A
refresh token is issued once; the copy is taken while the account is active and
cannot be fetched again. So one failed decode, followed by any ordinary edit,
signs every inactive account out for good.

Adding a single non-optional field to `StoredAccount` would have put every
install on that path — which is exactly what was found for `Preferences`
yesterday, with a worse ending.

**What it does now.** A read that succeeds and a decode that does not sets a
flag. The list stays empty, so the interface honestly says there are no accounts,
and `persist()` throws instead of writing. Recoverable: a build that can read the
item again finds it intact.

**Three tests, and the middle one is the point.** The list reads empty; a
`forget` throws `WouldOverwriteUnreadableAccounts` and the item is not written to;
a readable list is still written to exactly as before, because the refusal is
about the one case and not about writing.

**Verified by removing the guard**: four checks fail, one of them counting the
writes to the item. The live app was relaunched afterwards and still reads its
four accounts.

**Left for a later pass.** The other three persisted types have the same
fragility and softer endings — an unreadable snapshot costs the widget its data
until the next poll, an unreadable history costs the chart. Worth the same
treatment; not worth conflating with the one that loses credentials.

## The rest of the persisted types

**Decision.** The shared snapshot decodes field by field, and the history decodes
its readings one at a time. Both were left for this pass a day ago, deliberately,
so the one that loses credentials was not conflated with the two that lose a view.

**The snapshot.** A widget that cannot decode the file shows "No accounts found",
which reads as an app nobody has set up rather than a file that would not parse.
`pollingEvery` was made optional when it was added, for exactly that reason —
which protected the *next* field and nothing after it. Every field now falls back
on its own: a missing `rowLayout` costs the layout, not the reading.

**The history.** The synthesised decoder refuses the whole array if one element
is malformed — a truncated write, a field a later build added — and
`UsageHistoryStore.load` answers a refusal by starting empty. A month of readings
is not something to lose to one bad entry. Readings are decoded individually now
and a bad one is dropped; the chart already draws gaps honestly, so a few missing
points are a shape it knows how to say.

**Two tests each, and one of them nearly did not count.** Removing the snapshot's
decoder and re-running looked like a pass: the check failed by *throwing*
`DecodingError`, and the probe was grepping for the expectation's message. Counted
the failures instead and it was there. Third time in this log a measurement has
been wrong in the same direction — looking for the failure I expected rather than
for any failure.

**Where this ends.** Four persisted types, four treatments: settings decode field
by field, the account list refuses to be written over when unreadable, the
snapshot decodes field by field, the history reading by reading. The shape was
always the same — a synthesised decoder is all-or-nothing, and every one of these
files is read by something that answers "nothing" without saying why.

## The same gap, one level down from yesterday's fix

**Decision.** `AccountSnapshot` decodes field by field, and the snapshot's
`accounts` array decodes row by row.

**Why.** Yesterday's snapshot decoder falls back on a field it cannot read — and
for `accounts` the fallback was `[]`. So a field added to `AccountSnapshot` by a
later build would make every row refuse, the array fall back to empty, and the
widget say **"No accounts found" about accounts that exist**. That is the exact
sentence the decoder above it was written to stop being said untruthfully,
reintroduced one level down by the fix itself.

**Two changes, and they answer different failures.** A row decodes field by field,
so a build that knows one field fewer still draws the row: the name falls back to
the identifier, the plan to a dash, the windows to none, the freshness to "we do
not know when". And the array decodes row by row, so one entry that will not
parse costs that entry rather than the list.

**What is still refused, on purpose.** A row without an `id` or a provider. There
is nothing to fall back to and nothing useful to draw; dropping it is the honest
answer, and the test says so.

**Verified by removing each.** Without the row's decoder, four checks fail.
Without the row-by-row array, the one that plants a bad entry between two good
ones fails. Both restored, both platforms build, and the live app writes four
named rows into the container the widget reads.

**Five types now, and the same sentence under all of them.** Settings, the
account list, the snapshot, the history, and the rows inside the snapshot. Every
one was read by something that answers "nothing" without saying why — an empty
window, an empty widget, an empty chart — so an all-or-nothing decoder turns a
field nobody thought about into a lie about the data.

## Four captions in one place, two with a full stop

**Decision.** The phone's and the widgets' empty-state captions end in a full
stop, as the window's two already did.

**Why.** The phone app had not been run since five decoders and three screens
changed, so it was run. Everything holds: the reading time in the toolbar, the
refresh control, and — correctly, on a simulator with no keychain accounts — "No
accounts found".

Which is the sentence three entries have been spent making sure is never said
untruthfully, and seeing it said truthfully was worth the launch on its own.

Under it sat the thing only a running screen shows. Four surfaces carry a caption
in that position:

    Claude Code's credentials cannot be read, so the account …shown.   stop
    Sign in to Claude Code or run Codex.                               stop
    Sign in on your Mac — accounts sync through the keychain           none
    Open Softcap to load data                                          none

All four are complete imperative sentences. Two took a stop and two did not, and
the split is by platform rather than by anything a reader could infer. The two
missing ones now have theirs, in each language's own punctuation — `।` for
Bengali and Hindi, `。` for Chinese.

**A mistake worth recording.** The first attempt appended the language's own stop
to the **key** as well as the value, so three catalogues ended up keyed on
`…data。` while the code looks up `…data.`. The key is the English phrase and is
the same everywhere; only the value takes its own language's punctuation. The
catalogue guard caught it immediately, naming the three languages and both keys.

**Seen, then seen again.** Rebuilt, relaunched, and the caption reads with its
stop on the screen. Simulators shut down afterwards.

## The log described, and a number that lasted one minute

**Decision.** The README says how this file is organised and how to read it. It
does not say how many entries are in it.

**Why.** The line was "decision log: what, why, and at what cost". Measured: of
the entries here, 94% say what was decided and why, and **42%** name a cost. That
is not a fault in the entries — a correction of a mistake has no cost worth
naming — but it is a description promising more shape than the file has.

More usefully, the line said nothing about the one convention a reader needs.
This file is **append-only**: an entry is never rewritten, because the reasoning
in it was true when it was written, and where a later entry found an earlier one
wrong it says so rather than editing it. Two begin *Correction*. Without knowing
that, the two entries that contradict earlier ones read as carelessness rather
than as the record working.

**Structure, checked while there.** 161 headings, no duplicates. One near-pair —
the macOS widget's app group and the iOS widget's — and they are two platforms,
not one entry written twice.

**The number I had just written, deleted.** The first draft of that README line
opened "161 entries". It would have been wrong by the time this entry was
committed, and it is exactly the defect five entries in this log are about: a
fact stated in two places with nothing joining them. Caught by reading back what
I had written before committing it, which is the only reason it is not the sixth.

**Not done, and why.** The macOS widget is the surface changed most in the past
week — reading age, `capturedAt`, `pollingEvery`, row-by-row decoding — and the
one never seen. Opening Notification Centre to look showed a locked screen: the
machine is unattended. Sending keystrokes at it is neither useful nor mine to do,
and the screenshot it produced was of the lock screen, so it went to the
quarantine. The widget is still unlooked-at, deliberately, and stays on the list.

## Hiding an account was read in three places and guarded in none

**Decision.** A scan requires the poller and the chart to consult
`hiddenAccounts`, and the Accounts pane to write it.

**Why.** The notification path was checked first — the landing promises three
things about it and `ThresholdNotifier` has fourteen tests, including that a
crossing suppressed by quiet hours is not delivered late. All three claims hold,
which is what an hour spent looking should sometimes conclude.

Hiding did not. The setting is written by one switch and read by two places, both
in `App/`, which has no unit tests. Delete either read and a hidden account
returns — to the window, the widget, or the chart — with the switch still off and
every one of the 367 tests passing. The chart's half is worse than it sounds: its
history would be drawn up to the moment it was hidden and stop there, and a
stopped line means, everywhere else in that chart, that nothing was measured. An
entry above is about fixing exactly that, and nothing was holding the fix in
place.

**A scan, and what it can and cannot say.** It cannot prove a filter is right.
It can refuse a version where nobody consults the setting at all, which is the
failure that is otherwise silent, and it names what breaks in each case rather
than saying a string is missing.

**Verified three ways.** The poller's filter removed, the chart's lines removed,
and the switch made to write a field that does not exist: each refused, with the
consequence in the message.

## One request is not a measurement

**Decision.** The deploy's verification asks twice before deciding, and the digest
comparison retries around itself rather than through a variable.

**Why.** A routine live check answered `000` for `/` while the five other paths
answered `200`. Three retries a second later all answered `200` in about a sixth
of a second each, with the right headers and matching content: one connection
that failed, not a site that was down.

`deploy.sh` could not have told those apart either. It ran unattended every
twenty minutes and made every judgement on a single request, so a blip after a
deploy that had already landed would report failure. In a loop that runs itself,
a false failure is worse than a missed one — it teaches whoever reads the output
to stop believing it.

**The first version of the fix broke the thing it was protecting.** Routing the
body through `try_twice` meant a command substitution, which strips trailing
newlines and mangles bytes, so every one of the six digests stopped matching. The
deploy said so immediately — `200 but serving something else`, six times — because
it compares digests and not status codes. An entry from weeks ago argued for
exactly that, and this is the first time it caught something written in this
script rather than shipped by it.

The body now goes straight into `shasum` and the retry wraps the comparison. Six
digests match again, and the deploy exits zero.

**Failures still fail.** One header check was pointed at an unroutable address:
the deploy took 59 seconds, exited 1, and named which header was absent. Two
attempts and a `--max-time 20` are what those 59 seconds are, and they are worth
paying at the end of a deploy rather than at the start of a false alarm.

## A setting that existed only in the file it was saved to

**Decision.** The shortcut that opens the window is registered, has a control in
Settings, and a test refuses a version where either is missing.

**Why.** Sweeping every preference for whether anything guards the code that
reads it left one: `refreshHotKey`. Following it turned up something else —
`openWindowHotKey` is read by **nothing at all**.

It has been in `Preferences` since the settings screen was built: declared,
defaulted, persisted, and given a per-field decoder a few days ago.
`HotKeyID.openWindow = 1` sits in `App/HotKeys.swift`. The plan for that screen
specified both halves — `hotKeyRow("Открыть окно", path: \.openWindowHotKey)` and
an `onChange` that registers it. Neither was written. So the setting could not be
recorded, and if it somehow held a combination nothing would have listened for it.

Two entries in this log say "both hot keys" while listing what a person can
configure. I wrote both.

**Where the registration goes, and why not beside the other one.** In
`StatusItemController`, which owns the popover and the status item the popover
hangs from, and which is installed at launch. `AppModel` carries a comment
explaining that registration in a lazily-created object does nothing until that
object exists — the settings scene had that fault once. The controller does not.

**The action is the button's own toggle**, so the shortcut closes what it opened,
and the app is activated first: without that the window appears while the keyboard
stays with whatever was frontmost, which the popover code already knew.

**Verified from both ends.** The registration pointed at the other identifier:
refused, naming what would then hear nothing. The row removed from Settings:
refused. Both builds clean, and the live app relaunched and kept polling.

## What the plans specified and the code never got

**Decision.** Six tests for `remainingCompact`, the countdown in the menu bar.

**Why.** Yesterday's find — a setting the plan specified and nobody implemented —
suggested asking the question wholesale. Every type, function and setting named
in the three plans was checked against the code. Most of what came back is
renames the log already accounts for: `StatusCheckerApp` became `SoftcapApp`,
`AccountRowView` became `AccountRow`, and `formatRemaining` became `RemainingTime`
plus a formatter, which the localisation spec argued for.

Two things were real.

**`unregisterAll`, and it is not needed.** `register` unregisters that id first
and a nil combination unregisters and stops, so changing a shortcut releases the
old one. The planned sweep would only have mattered at teardown, where the
process exiting does it.

**`remainingCompact` had no tests at all.** The plan specified two cases for it
and neither was written; the function then survived the localisation rewrite
while the tests that were meant to cover it did not exist to be rewritten. It
produces the single string this app is looked at for — `0:41` in the menu bar —
and nothing checked it.

Six now: a clock under an hour, hours and minutes, **minutes padded to two
digits** because "2:4" is not a time, days collapsing above a day because "23:00"
reads as tonight rather than tomorrow, a dash for nothing left, and the day unit
differing across the ten languages since it comes from the catalogue.

**Verified by breaking two.** The zero-padding removed: two fail. The day
collapse removed, so five days render as a clock: the one that says a countdown
of days should not look like a clock fails.

**What the sweep says about the plans note.** It calls them "all carried out",
which was written from their own ticked checkboxes. Two items were not, and one
of them was a feature. The note is not wrong about the work — it is wrong about
the checkboxes being evidence.

## Correction: the plans' checkboxes were never ticked

**What was written.** The note in `docs/superpowers/plans/` said the three plans
were "all carried out" and that "the checkbox lists are the plan's own progress
tracking and all of it is ticked".

**What is true.** There are 214 checkboxes across the three plans and **not one is
ticked**. The claim was written without counting them. And "all carried out" was
already disproved a day later by finding two specified things missing from the
code — the shortcut that opens the window, and the tests for the menu bar's
countdown.

So the note asserted the opposite of the truth twice, in a document written to
help a reader trust the plans. It now says what they are: nearly all of it was
built, they are not a record of what was finished, and the way to know whether
something in a plan exists is to look for it in the code.

**The same question, asked of the specs.** Every name they use, against the code.
Three are renames the log accounts for. The fourth is not: the module table in
the monitor design lists `ThresholdNotifier`, and no such name is in the code —
the type is `ThresholdTracker`, and the *sending* it was named for lives in
`AppModel`.

**The files still carried the old name.** `ThresholdNotifier.swift` and
`ThresholdNotifierTests.swift` held a type called `ThresholdTracker`, so a reader
grepping for the name in the spec found a file and no declaration, and a reader
grepping for the declaration found it in a file named after something else. Both
renamed; both builds and the suite unaffected.

The spec keeps its own wording, as a document of what was designed. The README
now says where the name went, which is where a reader stands when deciding to
open it.

**How this was found, and the near-miss.** The sweep reported `ThresholdNotifier`
missing from the code and my first thought was that the instrument was wrong
again — it had been, three times this week. Checking took one `grep` and the
instrument was right. Suspecting the tool is a habit worth having and not worth
trusting.

## A rule that fit yesterday's bug and not this codebase

**Decision.** One filename corrected. The sweep that suggested more was the wrong
rule, and saying so is most of this entry.

**Why.** Yesterday a file called `ThresholdNotifier.swift` was found holding a
type called `ThresholdTracker`. The obvious generalisation — every file should be
named for what it declares — was run across all 119 Swift files and returned
thirty. Nearly all of them are the convention working: `Models.swift`,
`HotKeys.swift`, `Formatting.swift` hold several related types on purpose, and a
test file's suite is named as a sentence — `ChartNamesTests.swift` declares
`TheChartDrawsWhatItCanName`, which is the house style and reads better than the
alternative.

So the rule that caught yesterday's bug is not "file name equals type name". It
is **a document pointed at a name that exists nowhere** — which is why the spec
found it and this sweep mostly did not.

One was real and it was mine: `FaviconMatchesItsDeclarationTests.swift` has
declared `TheHeadAndTheFilesAgree` since I widened that suite two days ago and
left the filename behind. Renamed.

**The right rule, run properly.** Every name and path the README puts in
backticks, against the code and the filesystem. Three came back and all three are
the check's own limits: `Caddyfile` is a file rather than a type, `deploy.sh` is
prose shorthand for a path the same page gives in full a few lines above, and
`ThresholdNotifier` is there because yesterday's entry deliberately explains that
the name is gone.

**And the landing gained a sentence.** The shortcut that opens the window started
working yesterday and the page said nothing about either of the app's two
shortcuts. It now mentions one, in the cell about the menu bar where it belongs,
and a test refuses the page promising a shortcut that nothing registers — a claim
a reader takes on trust and never checks is exactly the sort to tie down.

## The certificate renews itself until it does not

**Decision.** `deploy.sh` reads how many days the certificate has left and fails
under twenty.

**Why.** Everything else about the site is checked on every deploy — the bytes,
the headers, the route surviving a reboot, what a wrong URL gets. The one thing
that ends the site outright was not: a certificate that stops renewing gives no
sign until the day it expires, and then every visitor meets a browser warning
instead of the page.

Let's Encrypt issues for ninety days and kamal-proxy renews at about thirty left,
so twenty means two renewal windows have gone by unnoticed. It reads 88 today,
which is a certificate that renewed on the first of the month exactly as it
should.

**The check's first version died before it could speak.** Pointed at an
unreachable host it exited 1 with no message — `set -e` and `pipefail` abort the
script at the assignment when the pipeline fails, so the branch written for
precisely that case was never reached. `|| true` around the substitution, and it
now says "could not read the certificate's expiry" and fails on purpose rather
than by accident.

That is the second time this week a guard has been written in a way that could
not report the thing it was guarding — the first was the commit hook treating a
filter that matched nothing as success. Both were found by asking what the check
does when the world is wrong, rather than when it is right.

**Verified both ways.** The threshold raised above the real figure: the deploy
names the number and exits 1. The host made unreachable: the deploy names the
unreadable certificate and exits 1. Restored, eleven checks pass.

## Room on a disk that is not only ours

**Decision.** The deploy refuses to ship when the host has under five gigabytes
free, and says so when it cannot read the figure.

**Why.** The certificate check finished the list of things that end the site
outright, except one. The droplet is shared: other projects build and pull on it,
so the disk can fill for reasons nothing in this repository controls. The symptom
would be a container that does not come back after the restart this script
performs on every run — a deploy that took the site down and could not put it
back.

Five gigabytes on a 154 gigabyte disk is about three per cent: late enough not to
fire on ordinary use, early enough to leave room to act.

**What the measurement showed, and what was left alone.** 105 GB free, 33% used —
healthy. But of the 50 GB used, Docker holds 37.9 GB of images with 32.6 GB (85%)
reclaimable, and 9.9 GB of build cache with 9.1 GB reclaimable. Around 41 of the
50 could be freed by a prune.

Not run. `docker system prune` on a host carrying other people's production could
take an image one of them needs to restart, and this repository's business there
is one static site in one directory. The figure is recorded because the trend is
one-directional and somebody should know; acting on it is the owner's.

**Verified both ways.** The threshold raised above the real figure: refused, with
the number. The path made unreadable: refused, saying it could not read rather
than assuming zero — which is the same distinction the account-list decoder makes
between "nothing stored" and "stored and unreadable".

## Reading zero as evidence

**Decision.** No code changed. Recorded because a tool used all week for
observing the running app does not work here, and its silence was being read as
the app's.

**What happened.** With one account at 87% — above the 80% threshold, crossed
while the app was running — this was the first chance to watch the notification
path do something. `log show` returned nothing for the app's subsystem. Then
nothing for the process. Then, checked properly, **nothing for Finder, and
nothing at all for the whole system over two minutes**, which is impossible on a
running Mac.

So `log show` cannot read the persisted archive from this shell. Every zero it
returned this week meant "cannot look", not "nothing there" — including one
earlier the same day, from which the conclusion "no notifications have fired" was
drawn. That conclusion was probably true for other reasons and the evidence for
it was worthless.

**`log stream` works.** Filtered to the app's own subsystem for seventy-five
seconds, it caught a poll:

    E  Softcap[…] [app.softcap.Softcap:poll] <account>: no usable refresh token;
                                             sign in again

Twice, once per failing account. So the app records what it cannot do, at error
level, with the account and the reason — which is the opposite of the conclusion
the silent tool was about to support.

**The fourth instrument failure this week, and the worst kind.** The others
announced themselves: a probe that matched a prefix, a grep that coloured its
output, a regex that found nothing. This one returned a well-formed, plausible
answer — zero — that happened to be about the tool rather than the subject. A
number is not a measurement until something has shown the instrument can produce
a different one.

**Live observation from here is `log stream`, not `log show`.** Written down so
the next attempt does not spend the same half hour.

## The log said the same thing every five minutes

**Decision.** A failing account is logged when the failure starts or changes, and
once more when it clears. Not on every poll.

**Why.** Being able to read the log at last — `log stream` works here where
`log show` does not — showed what it actually contains: two identical error lines,
one per account needing a sign-in, written by every poll. At five minutes that is
**576 lines a day**, for a condition that is already on screen in the window, the
widget and the phone, and that does not change until somebody signs in.

The cost is not the disk. It is that the next genuinely new error — a network
failure, a malformed response — arrives into a log made of the same two lines
repeating, and is read past.

The argument was already in this file, a few lines below the code that had the
fault: `ThresholdTracker` reports a crossing "once per crossing rather than once
per poll", because otherwise a five-minute background poll turns into a stream of
alerts. The same reasoning, never applied to the log.

**It also says when it stops.** A recovery line, so a reader can see how long a
failure lasted rather than watching the lines simply cease — which is
indistinguishable from the app having stopped polling.

**Verified live, across two polls.** Relaunched, then streamed for three hundred
and eighty seconds — long enough to cover the startup poll and the five-minute
one after it. Two lines, both from startup, one per failing account. The second
poll wrote nothing. Before this change there would have been four.

**Made possible by the previous entry.** This was invisible for as long as the
tool being used to look returned zero for everything.

## What the app's first fifty seconds look like

**Decision.** No change. Recorded because the launch had never been watched, and
because it explains why the widget cannot be.

**The launch is clean.** Streamed from before `open` until fifty seconds after:
447 lines, of which four are errors. Two come from Apple's own availability
check and have nothing to do with this app. The other two are its own, naming the
two accounts that need a sign-in — correct, and now written once rather than
every five minutes.

No faults. No keychain error, no notification-permission error, and
`container_create_or_lookup_app_group_path_by_app_group_identifier: success` —
the channel the widget reads the snapshot through, confirmed at launch rather
than inferred from the file appearing. The first poll finished 3.2 seconds after
launch, so nothing in that sequence blocks.

Every one of those was previously an assumption. The entry two days ago about the
startup order — timer, watcher, hot key and wake handler armed *before* the first
poll, because a poll can block on a keychain prompt — was reasoned from a bug
seen twice and never watched working.

**And the widget cannot be observed, for a plainer reason than the locked
screen.** Its extension is not running and was not asked for a timeline in
seventy seconds. WidgetKit only starts an extension for a widget somebody has
placed, so there is nothing to watch until one is. That closes a line that has
been open on the list for a week: it is not a thing to keep trying, it is a thing
that needs the owner to add the widget once.

## The promise on the page about what does not happen

**Decision.** Guard the landing's privacy sentence the way its numbers are
guarded, and stop expectations from printing whole documents.

The page says: *"Credentials stay in the keychain, never copied into preferences
or logs. No telemetry; nothing else leaves your Mac."* Every other claim there is
about a feature, and a feature that stops working is visible. This one is about
an absence, and an absence stops being true silently — one convenient line adding
a crash reporter, one field on the settings struct, one `log.error` interpolating
a token while somebody chases a sign-in bug. The page would go on saying it.

It is true today, checked host by host. Every absolute URL in the Swift sources
is one of five: the Claude usage endpoint, the two OAuth endpoints, the loopback
PKCE returns to, and `https://api.openai.com/auth` — which is not fetched at all,
it is the namespace of a claim *inside* a Codex token. `www.apple.com` appears
six times and is the plist DTD, which nothing has resolved since 2003. Neither
would have been obvious from the grep, and either could have been reported as a
leak by a check that counted strings.

So `NothingElseLeavesYourMac` holds five things: every host is one of the five,
each listed with the reason it is there; exactly one file builds a `URLRequest`,
which is what makes the host list worth reading, since a second builder could
assemble a host from pieces the scan never sees; no setting is named for a
credential; no log line writes one unredacted; and the page still makes the
promise, so the suite fails loudly rather than guarding nothing.

**A guard whose failure cannot be read is half a guard.** The first version
failed with 29 000 characters of HTML ahead of the sentence saying what to do —
`#expect` prints its sub-expressions, and `page.says(…)` makes the page one. Seven
existing checks in two other suites had the same shape and would have dumped the
README. Each suite now asks through a `…Says(_:)` that takes only the phrase, so
the failure reads `(try Self.pageSays("No telemetry") → false)`. These checks
exist to fire on an edit years from now; the report is the whole product.

**Cost.** Each of the five was proven by breaking what it guards — a telemetry
host, a second request builder, a `refreshToken` setting, a token logged
`.public`, the sentence removed. All five refused, each naming the fix.

Twice the thing that failed was the check *of* the check. A `--filter` naming a
test that does not exist ran nothing and reported success — the defect this log
already records against the pre-commit hook, reappearing in the verification of a
guard against it. And a mutation by `sed` silently did nothing because the phrase
it targeted wraps across a line in the file while the test squashes whitespace
before matching. Both times the guard was fine and the instrument was not, which
is now four instrument failures this week against one real defect found by them.

## The requirement a search engine could read and a reader could not

**Decision.** Put the systems Softcap needs on the page in words, and hold the
copies together.

`"operatingSystem":"macOS 14, iOS 17"` has been in the structured data since the
page was written, so a search result could state the requirement while the page
itself never did. "Can I run this?" is the first question a reader has and the
page's technical section — the one addressed to people who read that part — did
not answer it. A `Requires` row now leads that list.

The floor is set in `Package.swift`, so the check reads it there rather than
naming a version of its own: the visible sentence, the JSON-LD and `project.yml`
must all agree with the manifest, and raising the target fails four expectations
until every copy follows.

**The guard was vacuous when first written, and only deleting the row showed
it.** It strips `<style>` and `<script>` before matching, because the whole file
contains "macOS 14" in the JSON-LD whether or not a reader can see it — that is
the exact failure it exists to catch. Written with
`replacingOccurrences(of:options:.regularExpression)`, the strip removed nothing:
`.` does not cross a newline by default, and both blocks span lines. The check
matched the JSON-LD and passed with the visible row deleted. It now uses
`NSRegularExpression` with `.dotMatchesLineSeparators` and refuses to run at all
if either block is still present afterwards.

That is the same defect as a `--filter` matching no test, one layer in: the
machinery ran, reported success, and had examined the wrong text. Three of this
week's four instrument failures have now been of that one shape.

**Also, procedurally:** reverting a mutation with `git checkout -- site/index.html`
threw away the row itself, which was not committed yet. The suite went red
immediately and said why, which is the argument for adding the guard before the
copy rather than after.

**Checked live, unchanged:** plain `http` answers 301 to https; `/.git/config`,
`/.env`, `/Caddyfile`, `/dist/`, `/site/index.html` and two traversal spellings
all return the 404 body rather than a listing or a file; `robots.txt` and
`sitemap.xml` serve with the right content types. Nothing in `site/` reaches the
web except the six files `SERVED` names, and `rsync --delete` keeps it that way.
`www.softcap.app` still has no DNS record — that needs the DigitalOcean API and
stays with the owner.

## Rendering the page and looking at it

**Decision.** Draw the widget on the desktop the hero already shows.

Everything about this page had been checked structurally — widths, hashes,
headers, whether a phrase is present — and nobody had looked at it. Rendering it
headless at 1440 px in both palettes, and at 390 px through an iframe, showed one
real fault: two thirds of the hero's stage was flat grey. The stage is a desk
with the window hanging off the menu bar, and at desktop widths the empty part
read as an image that had failed to load.

A desk is where the widget lives, and the page had been describing a widget in
words without ever showing one. The small size draws what `compact` in
`LimitsWidgetView` draws: the busiest account, its percentage, and when it frees
up. So the three values are not free — they are the largest meter in the window
mock beside it, the account carrying that meter, and its remaining time. A test
holds the two pictures together and holds the app to still picking the busiest,
because a page that draws the same app twice now draws it three times.

The three other things looked at and found sound: both palettes render correctly
through `html:has(:checked)`, the phone layout stacks and centres with the
pointer dropped, and the new `Requires` row sits where it was meant to.

**Cost.** Three instrument failures before a single pixel was read.

`zsh` does not word-split an unquoted expansion, so `set -- $v` put
`"light 1440,3400"` in `$1`: the window size was never passed, and the files were
named `light 1440,3400.png`. Then `sips` on the name I expected printed nothing,
and a `tail -2` of that nothing produced a plausible `756×469` — which is how a
size that was never measured nearly became evidence. Chrome's own stderr had been
sent to `/dev/null`, so none of it surfaced. Measure the instrument, then read it:
this log has said so four times and the count is now five.

**And the same mistake as two entries ago, within two sessions.** Reverting a
mutation with `git checkout -- site/index.html` threw away the widget, because
the widget itself was not committed yet. The entry recording it the first time
described what happened rather than what to do, which is why it did not take.
The rule is: **commit the work before mutating the file to test the guard.** A
scratch copy happened to survive this time; that is luck, not method.

## Looking at the image every shared link shows

**Decision.** Give the preview the headline's shape, and join the two files that
draw it.

`og.png` is what appears in Slack, in a message, in a search result — seen before
the page is, and by more people. It had never been looked at either. It broke the
headline after "subscription", so "limit," and "on one screen." ran together on
one line with the colour changing mid-phrase. The sentence is written as two
halves and the preview showed it as one, inverted.

The page had already solved this: `h1 em{display:block}`, with a comment saying
the second phrase is its own line by construction rather than by luck, because
sized in `ch` it breaks wherever the reader's font runs out of room. The template
never learned it, and nothing connected the files — the same defect as the icon
sizes, the theme colour and the app group before it. The type is now sized so the
first half fits a line on purpose, and a test requires both files to give the
second half its own line.

**Cost.** The bug was invisible to everything already guarding this pair. A test
requires the template to repeat the page's headline *text*, and it did: the words
were identical and the layout was not. Checking that two documents say the same
thing says nothing about their showing it the same way.

**And the running instrument problem, again.** Answering "why are there two menu
bar icons" with `ps | grep -v claude` returned one process, because the older app
is running out of `~/.claude-trash/` and the filter meant to drop this session's
own processes dropped the answer with them. Sixth this week. Rerun without it and
both are plainly there.

## The chart is dated, and dates age

**Decision.** Warn at deploy time when the chart's newest label falls behind.

Looking at the rest of the page at full resolution — the middle and lower thirds,
through an iframe offset so nothing is scaled down — found the sections, the
cards and the facts sound, and the chart correct: the break really is `alex`'s,
and the legend, the line colours and the coloured word in the prose all agree.

What it also showed is that the chart carries real dates, 4 August to 31 August.
That is what makes it read as a month of somebody's usage rather than a diagram,
and it is also a slow leak: in March, a page whose only picture of "over time"
ends last August reads as one nobody tends. Every existing check would still
pass, because nothing about it is wrong — only old.

`deploy.sh` now reads the last label and says how far back it is. A warning, not
a failure: a stale illustration is no reason to refuse an unrelated fix. But
labels it cannot find *do* fail the deploy, for the reason this log keeps
returning to — a check looking in the wrong place must not read as nothing to
report. Proven on all three inputs: today's date, one six months old, and the
labels deleted.

The chart cannot compute its own dates. The page carries no script and the policy
that forbids one is the reason its Content-Security-Policy can stay at
`default-src 'none'`, so a static label with something watching it is the whole
of what is available.

**Considered and left alone:** the second heading breaks as "Measuring a quota
should not / spend it", which splits the verb phrase. Forcing the break after
"quota" means narrowing every `h2`, and at that width two of the others break
into three lines. The cure is worse.

## The page promised a sign-in that sticks

**Decision.** State the condition, because the sentence was not true as written.

The window showed two Claude accounts as *Sign-in required* for someone who had
signed into them the day before. The page said: "Sign into each plan once, the
ordinary way, and they stay on screen together." They had, and it had not.

Nothing is broken. `syncWithCLI` runs before every poll and copies whatever token
the CLI currently holds — and that is the *only* moment the copy can be taken. An
account that was active only while the app was closed leaves nothing behind, and
once `/login` moves the CLI on, that account's token is out of reach. Separately,
Anthropic rotates a refresh token on every use, so a copy the app took is
invalidated if the CLI later refreshes the same account; `accessToken(for:)`
clears a copy the server rejected rather than retrying a dead credential, which
is the deliberate choice recorded when that code was written.

Both paths end at the same row and the same words, and both are honest behaviour.
The sentence describing them was not: it promised a property that holds only when
the app is running at the moment of sign-in. It now says so, and the README
carries the longer version including the rotation case.

**The general shape.** Every guard on this page checks that a claim matches a
constant or a string in the source. None of them can check that a *promise about
what happens over time* is kept, and this one had been wrong since it was
written. It took somebody signing in and looking at the result. That is worth
remembering the next time a check passing is mistaken for a claim being true.

## The warning that could not arrive

**Decision.** Let the threshold tracker's memory outlive the process.

A weekly window sat at 91% having said nothing, and the landing says "it tells
you before you hit it". Four things were checked before the cause was found, and
the first two were wrong.

`ThresholdTracker` emits on a *crossing*: a reading below the threshold and one
above. `previous` lived only in memory. So a relaunch is indistinguishable from a
first run — nothing below to have crossed from — and the account stays above
until the limit resets, which for a weekly window is up to seven days. Not a late
warning: none. Changing any notification setting rebuilt the tracker and erased
the same thing.

The baseline is now carried across a rebuild, and restored at launch from the
snapshot the last run already writes for the widget — no new storage. Only if
that reading is under fifteen minutes old: this is meant to survive a relaunch,
not to announce a transition from three days ago. Seeding records where things
stood and emits nothing, because what happened before the app started is not news
it can honestly deliver.

Verified in the running app rather than argued: `baseline restored from a reading
46s old, 4 accounts`, on a relaunch.

**Two wrong theories, both killed by looking.** First: the request for permission
fails silently for a development build, because `try?` discards the error — the
very defect the comment above that function records as already having happened
once. The log says otherwise: `Requesting authorization with options 6` then
`didGrant: 1 hasError: 0`. Permission is granted. Second: the app is absent from
`com.apple.ncprefs`, which listed 126 other applications — an absence that means
nothing, and was one step from being reported as the cause.

**And the instrument, a seventh time.** The restore was invisible, so it now logs
once per launch — and that line did not appear either, because `log stream` shows
nothing below default level without `--level info`. Which also explains why
`imported N codex readings` had never been seen in any capture this week. Every
`.info` this project writes has been invisible to every observation made of it.

## A number nobody could check, in a line written to be checked

**Decision.** Report what the merge kept, not what it was offered — and guard the
shape of a sentence, not only its presence.

Now that `--level info` makes them visible, the app's own log reads as five lines
per launch. One of them was wrong. `imported 73 codex readings` reported
`samples.count`, the number the session files hold; `merge` deduplicates, and
since the first run it had added none of them. The history file confirms it: 555
readings, 555 distinct keys, no duplicates at all. The line had been announcing
work it was not doing, on every launch, for as long as it has existed.

`merge` now returns how many were new and the line carries both figures.
Observed: `imported 0 of 73 codex readings`.

**And two log lines were misshapen.** They read "…s old,             4 accounts".
Nothing was wrong with the Swift — the gap was baked into the literal by the
editing, and a multi-line string keeps whatever is inside it. It survived a
build, a full test run and a commit, because every check here asks whether a
string is *present*, and it was. `SentencesReadAsSentences` now asks the other
question, of the two surfaces where the answer matters: the ten catalogues a
reader sees, and the sentences the log carries. Both halves proven by putting a
gap back.

Its own floor caught it first: written expecting ten logged lines, it found eight
and refused to run rather than pass on a thin scan. There are five multi-line log
calls in the sources and eight lines of text between them; the floor is now five,
which is what is true.

**The same procedural mistake, a third time.** Reverting the mutation with
`git checkout -- App/AppModel.swift` destroyed the whitespace fix, which had not
been committed — the fix was made after the commit that preceded it. The rule
recorded twice already said "commit the work before mutating", and that was not
enough, because the work here *was* committed and then added to. The rule that
actually holds: **`git status` must be clean before breaking a file to test its
guard.** Not "have committed recently" — clean, checked, at that moment.

The new guard caught the loss, which is the first time one of these has.

## The thinned icon nobody was being shown

**Decision.** Put the small-size rule in `icon.svg`, where a browser will read it.

Below 40 px the mark drops its inner ring and thickens the outer one, because two
concentric strokes a few pixels apart merge into a smudge. That rule was written
into `make-favicon.sh`, which bakes the `.ico`, and an entry in this log explains
it. Extracting the three bitmaps and looking at them at eight times size showed
the rule applied correctly: one clean ring at 16 and 32, both rings at 48.

And none of that reaches anybody. The page declares `icon.svg` first and the
`.ico` as `alternate icon`; every browser that can render an SVG favicon prefers
the SVG, which is all of them. So the tab has been showing the full two-ring mark
at 16 px — the exact smudge the rule exists to prevent — while the thinned bitmap
sat unread in the file beside it. Rendered side by side the difference is not
subtle: a muddled blob against a legible ring gauge.

An SVG cannot ask how large it has been drawn, but a media query inside it
measures its own viewport, which for a favicon *is* the render size. Tested
before it was trusted: a probe copy rendered at 16 and 48 gave the thinned mark
and the full one respectively. `icon.svg` now carries the rule, and the four
circles carry the classes it names.

**Cost.** The rule now exists twice — a shell script and a stylesheet — which is
the shape this log keeps recording as a defect. A test holds them to the same
threshold and the same thickened stroke, and refuses a media query whose classes
are on nothing: styling a class no element carries would satisfy a check that
only looked for the query, while changing the drawing not at all. Proven by
breaking each of the three.

Writing that test also found its own first bug — matching `stroke-width="\d+"` in
the shell script found the width being replaced *away*, not the one replaced in.
The expectation printed both numbers, which is the only reason it took a minute
rather than an afternoon.

## Correction: the check that reported nothing to push

Written the same day as the entry above it, because it nearly turned that entry
into a false report.

`git log --oneline @{u}..HEAD | wc -l` printed 0 and was read as "everything is
pushed". `@{u}` did not resolve, the error went to `/dev/null`, and `wc -l`
counted the zero lines of an empty failure. Asking the server directly —
`git ls-remote https://…` — showed it three commits behind.

Same shape as `swift test --filter` matching no test, as the width check with an
empty list, as the four file walks that found nothing: **a query that fails
produces the same output as a query that finds nothing, and only one of those is
good news.** It is the most frequent single mistake in this log, and this is the
first time it was about to be reported to a person as an accomplished fact.

The rule that follows: a claim that work has reached somewhere else is checked
against that somewhere, not against a local ref that a failed command left stale.

## Finishing what the favicon fix started

**Decision.** The header mark follows the same rule, and the guard covers all
three copies of it.

Thinning `icon.svg` below 40 px left the page inconsistent with itself. The
header draws the same mark inline at 26 px — below the threshold — and still
carried both rings, so the tab and the header showed different marks inches apart
on one screen. That is the exact thing the older brand-colour guard was written
to prevent, arriving in a new form, and it arrived because of the previous fix.

Rendered before and after: the header at 26 now matches the tab at 16, and the
mark at 48 still carries both rings. The rule exists in three places — the shell
script that bakes the `.ico`, the media query in the vector, the page's own
stylesheet — and one test holds all three to the same threshold and the same
thickened stroke. It also fails if the header ever grows past the threshold while
still thinning, which is the opposite mistake.

**The guard had to be fixed before it could be proven.** It located the header
mark by `width="26"`, so changing the width failed the *search* rather than the
size check: the one assertion about how large the mark is drawn could never be
reached. Found by trying to break it and getting no failure message — a mutation
that produces silence is the same signal as a scan that comes back empty.

**And nine failure messages could not be read.** Extending the whitespace guard
to expectation messages found that every check written this session held a run of
spaces in the middle, from the same editing that mangled the two log lines. The
surface nobody looks at until something fails, when the message is all there is.
Only blocks opened on an `#expect` or `Issue.record` are scanned: a multi-line
string in a test can also be an expected value, and columns in one of those may
be aligned on purpose.

**The push from the previous session landed.** SSH to `github.com` still hangs
during banner exchange although the port accepts a connection; `gh` is
authenticated, so the same push went over HTTPS with its credential helper, as a
one-off with nothing written to any config.

## The fourth copy of the mark

**Decision.** Join the app's icon generator to the vector on the numbers that
carry meaning, and leave alone the one that does not.

The same mark is drawn in four places. Three were joined last session; the
fourth, `tools/make_icons.swift`, draws it in CoreGraphics for the Dock, the menu
bar and the phone, and carries its own constants. It agrees with the vector on
all three: the threshold is 40, the weekly ring is 0.65 full, the five-hour ring
0.30 — and `stroke-dasharray="85.8 131.9"` on radius 21 is 65.0% of that circle,
`21.7` of `72.3` is 30.0%. Checked by computing it rather than by reading it.

Nothing had joined them. A test now does, and it computes the vector's fraction
from the dash and the radius rather than matching the literal, so changing either
number in either file fails. Proven three ways.

**Not the stroke weight.** The generator thickens the small ring to 0.135 of the
side and the vector to 7/64 — 8.6 against 7, at the same nominal size. Rendered
side by side at 16 and 32 both read the same, and the difference is what two
different rasterisers wanted. Forcing them equal would be pinning a number that
was tuned by eye against a pipeline, so the guard names the exclusion instead.

**Checked and sound:** the preview template draws the mark at exactly 40, which
is the boundary, and the rule applies *below* it — so both rings there are right.

**The filter reported success on nothing again.** `swift test --filter` naming a
test that did not exist printed "Test run with 0 tests in 0 suites passed" while
the edit that was supposed to add it had failed its own assertion. Caught by
reading the count, which is the only thing that distinguishes it. The pre-commit
hook refuses this, so nothing could be committed on it; an interactive check has
no such floor and never will — the count in the line is the floor.

## The shape of the page for anybody not looking at it

**Decision.** Give the page a `main` landmark, and hold its structure with a
test.

Everything on this page had been examined for how it looks. Its structure — what
a screen reader is handed — had not. Auditing it found the headings sound: `h1`,
five `h2`, six `h3` nested under the right one, no level skipped. And one real
gap: there was no `main`. The header, five sections and the footer sat at the top
level, so the jump-to-content shortcut had nothing to jump to.

Adding it changed the render by **zero pixels** — rendered at 1440×3600 before and
after and compared the two images, which came out byte-identical. That is exactly
why nothing would notice it being lost in a restructure, so a test holds the
shape: one `main`, the headline and the sections inside it, header and footer
outside, and headings that step one level at a time.

**The same false alarm, for the third time.** Counting `<svg>` tags that carry
`aria-hidden` or `role="img"` reported eight unlabelled drawings. None of them
real: the menu bar strip is `aria-hidden`, and the window and widget mocks are
`role="img"` with a sentence each, so everything drawn inside them is spoken for.
This log already records that mistake, from the first time it nearly produced two
false defects — and it produced eight this time, in a check written by somebody
who had read that entry.

What makes it recur is that the naive version is the obvious one and its answer
looks like an answer. So the guard walks ancestors, and it fails if it finds *no*
drawing covered by one — because that is what a walk that has stopped tracking
them would report, and it would look like a clean pass.

**No skip link.** It is the usual companion to a landmark, but there is nothing
to skip: the header holds the mark and three radio buttons, and the page has no
links at all. A link that jumps past four controls is a control of its own.

## The words a developer checks first

**Decision.** Join the techniques the page names to the code that performs them,
and rename a test that said the opposite of what it asserts.

The section addressed to people who read that part names three things by name:
FSEvents, PKCE, and a core without AppKit. All three are true — `FSEventStreamRef`
in the session watcher, `code_challenge_method` in the sign-in, zero `import
AppKit` under `Packages/Core`. Nothing joined the sentences to the code. Swapping
FSEvents for a poll leaves the page naming FSEvents in confident English, which
is the failure this suite exists for. Both halves are held now, each proven by
breaking its own side.

**A test named the opposite of its assertion.**
`quietHoursDoNotLoseTheCrossingAfterwards` reads as "it arrives later"; it
asserts that nothing arrives at all, and its comment explains why — waking
somebody in the morning with the night's news is worse than dropping it. The
landing says the same in words: *nothing is delivered late to make up for it*. A
name that contradicts its own assertion is worse than none, and this project has
renamed for that before. It is now
`theNightsCrossingIsNotDeliveredInTheMorning`, and the page's half of the promise
is held beside it.

Proving that one took two attempts: the first mutation removed the reading
instead of freezing the baseline, which loses the key entirely and produces no
event either — a change that looks like the bug and is not it. The second held
the pre-night value, and the test failed as it should.

**SSH to GitHub is not a key problem.** Diagnosed properly rather than routed
around a fourth time: the connection to port 22 establishes, the client sends its
version string, and the server's banner never arrives. The same happens on
`ssh.github.com:443`, GitHub's own fallback — so the protocol is being filtered,
not the port, and there is nothing to fix in the repository or in a key. Pushes
go over HTTPS with `gh`'s credential helper, one-off, nothing written to any
config.

**One thing the page cannot do, and it is not mine to decide.** There is no way
to act on it: no build to download, no source to read, no way to be told when
there is one. That is honest while it is in development, and the alternative —
an address to write to, or somewhere to leave one — is a choice about collecting
people's details that belongs to the owner.

## A way back

**Decision.** Keep the version that was live, and offer it by name when a deploy
fails.

Every check `deploy.sh` runs happens after the files are already on the host —
unavoidable, since the point is to verify the *served* bytes. The consequence was
that a deploy failing its own verification left the broken page up with no way
back but forward. That is not hypothetical: a digest check once found six
mismatches after the transfer, and the site stood wrong until it was fixed
forward.

`dist` is now copied to `dist.prev` before anything is replaced, and
`deploy.sh --rollback` puts it back. Contents, not the directory: `./dist` is
bind-mounted into the container, so a rename would leave Caddy serving the old
inode under its new name — the mount follows the inode, not the path.

Two refusals matter more than the restore. It will not roll back to a snapshot
holding fewer files than the site serves, because restoring an incomplete one
takes the site down, which is worse than the broken page it is meant to repair.
And it does not check digests against this checkout: after a rollback the live
files are the previous version and are *supposed* to differ. It checks that every
URL answers and the page is whole, then prints both digests so whoever is looking
can see which version is up.

**Exercised against the live host, not reasoned about.** A rollback restored six
files and verified. A snapshot cut to one file was refused with the site
untouched. A wrong argument exits 1.

**Two mistakes on the way, both already in this log.** `ssh $SSHO host` put the
whole option string in one argument, because zsh does not word-split — so the
test that was supposed to hide the snapshot silently did nothing, and the
rollback that followed ran against an intact snapshot and looked like a pass.
And the guard on the floor checked that the function body *mentions*
`${#SERVED[@]}`, which it does twice more in its own refusal message: it passed
with the comparison deleted. Both were found by mutation producing no failure,
which is the only signal a weak check gives.

**Noted, not acted on:** this site lives in `/opt/softcap-site` while the
house convention on that host is `/opt/<name>-webapp`, which the neighbouring
sites follow. Renaming a live deployment directory to match a convention is a
risk taken for tidiness, and the compose file's bind mounts are relative to it.

## The half of the rollback that was missing

**Decision.** Snapshot everything a deploy replaces, not only the pages.

The way back added yesterday kept `dist`. The deploy also ships the `Caddyfile`
and the compose file, and a Caddyfile that does not parse stops the container —
a site *down* rather than a site *wrong*. So the snapshot was missing the worse
of the two failures it exists for, in the work of closing exactly that gap.

`prev/` now holds all three. The rollback names the configuration it put back, or
says plainly that the snapshot held none, because restoring two of three quietly
would look exactly like restoring all of them — the same shape of failure this
whole line of work is about.

**Proved on the live host with no outage.** The served `Caddyfile` was replaced
with a valid but different one carrying an extra header; the site stayed at 200
and the header appeared; the rollback removed it from both the response and the
file on disk. Testing recovery from a Caddyfile that *does not parse* would mean
taking the site down on purpose, which is not a thing to do to a live domain to
satisfy a check — the mechanism is the same either way, and this exercises it.

**Three mutations, two of which did nothing at first.** `$S` holding an ssh
command line was treated by zsh as one command name, so the substitution that was
meant to change the live Caddyfile never ran — and the rollback that followed
reported restoring the configuration, which looked like the test passing. Then a
Python replacement with the wrong escaping matched nothing, and the guard it was
meant to break stayed green. Every one of those is the same failure the guards
themselves are written against, arriving in the tooling used to prove them.

## Something that notices when the mutation did nothing

**Decision.** Stop proving guards by hand.

This log now records thirty-four separate mentions of one failure, and it is
always the same one: **a query that fails looks exactly like a query that found
nothing, and only one of those is good news.** It has arrived as a `--filter`
naming a test that does not exist, a `sed` matching nothing because the phrase
wraps across a line while the check squashes whitespace, a Python replacement
with the wrong escaping, `ssh $OPTS host` becoming one argument because zsh does
not word-split, `$S` holding a command line for the same reason, and
`git log @{u}..HEAD | wc -l` printing zero because `@{u}` did not resolve.

Every one of those was in the act of *proving a guard*, and every one produced
the appearance of a guard that works. Being more careful has been tried for a
week. `tools/mutate` is the other answer:

    tools/mutate <file> <old> <new> -- <command>

A replacement that changes nothing is an error, not a quiet no-op. The restore
comes from a copy taken before the edit, never through git — `git checkout --`
threw away uncommitted work twice. It refuses a file that is not clean at that
moment, which is the rule this log had to write down twice before it stuck. And
a check that stays green with the file broken is reported as a failure of the
check, because that is what it is.

All four behaviours were exercised, and the file came back byte-identical after
three mutations in a row.

**It caught something on its first real use.** Asked to break a phrase in the
README to prove the new guard, it refused: the phrase wraps across a line in the
file, so nothing matched. By hand that is a green test and a false conclusion —
the exact mistake, made again, by somebody who had just spent an hour writing the
tool that exists to prevent it. The tool said so in three lines and cost nothing.

**The guard on the tool needed the same lesson twice more.** Forbidding the
string `git checkout` failed on the tool's own docstring, which names it as the
thing that went wrong; it now looks for the operation, `["git", "checkout"]`. And
two README phrases were matched against the unsquashed file, which is the
line-break mistake `ReadingProse` already records three times.

## What the tool found on the guards it was built to prove

**Decision.** Audit the guards on the landing with `tools/mutate`, and fix the
two that were not guarding.

Fourteen mutations against the eight suites that read the page. Eleven were
caught. One was a bad mutation. **Two were guards that did nothing**, and both had
been written and believed for days.

**The appearance switch.** `theAppearancesAreTheOnesTheAppOffers` checked that
each of the three appearances had a radio with the right id. The radio is a pixel
wide at zero opacity — the label is the whole of the control a reader can reach —
so deleting `<label for="t-dark">` leaves the page offering two appearances, the
third choosable by nobody, and the check green. It now requires the label too.

**The chart's colours.** `theChartUsesTheAppsColoursInTheAppsOrder` read the
legend and the order the palette hands slots out in, thoroughly. It never checked
that `.chart .lN` is drawn in `--id-N`. Pointing `l1` at `--id-2` draws one
account's line in another's colour, leaves every assertion in that test true, and
makes the key beneath the drawing a lie about the drawing. The mapping is now
pinned.

Both failures are the same shape: **the guard checked the half of the fact that
was easy to reach.** The id is in the markup; the label is three characters
further. The legend is a row of dots; the lines are a stylesheet away. Neither
omission is visible from reading the test, which is why reading tests is not how
you find them.

**One of the fourteen was my own mistake, and the tool cannot catch that kind.**
Raising a row's 16% to 96% did not break "least loaded first", because that row's
peak was already 80 — the order stayed sorted and the guard was right to pass. A
mutation has to break the *property*, not merely change a byte; `mutate` can tell
you the file changed, not that the change means anything. Re-run against the row
that actually carries the order, it caught it.

## The hook that examined one suite in sixty-eight

**Decision.** Run the whole suite before every commit.

The hook was written for one failure and did that job well: personal data is in
the history from the moment it lands, so it cannot be fixed forward, and the
check for it has its own floor against a filter that matches nothing. It still
has its own message.

What it did not do was notice anything else. Yesterday a commit went out with two
tests failing — the hook ran, passed, and had examined one suite out of
sixty-eight. The failure was in another. Four seconds against one is little
enough to pay, and the alternative, on the evidence, is pushing red.

**Its own floor failed silently while being written.** The count of tests
examined was captured with `grep -oE`, which colours its output here, so the
value arrived wrapped in ANSI codes. `[ "$examined" -lt 100 ]` then failed with
"integer expression expected" — and a test that *errors* inside an `if` is simply
false, so the branch was skipped, the floor never fired, and the hook exited
zero. A guard against silent no-ops, silently doing nothing, in the same hour as
an entry about exactly that.

It reads the number with `sed` now and refuses anything that is not a number,
rather than comparing and hoping. Both floors and both refusal paths were proven
with `tools/mutate`: a failing test elsewhere, the personal-data suite renamed,
and the threshold raised past the real count.

**The README said a quarter of a second and nine checks.** It had been true. Two
of the three sentences describing this hook had drifted, which is the thing this
repository has a dozen tests to prevent — in the paragraph about the tool that
prevents it.

## The second sweep, and what a bad mutation teaches

**Decision.** Finish auditing the guards, and join the third place the page says
what it is.

Fourteen more mutations, across the suites the first sweep did not reach: the
hidden-account surfaces, both shortcuts, the four numbers the page quotes from
constants, the dependency check, the download-or-development contradiction. **All
of them held.** After the two hollow guards the first sweep found, that is the
more useful result: the rate is not one in seven.

Three of the fourteen failed at first and none of them was the guard's fault.
Changing one row's percentage did not break "least loaded first" because that row
was not the one carrying the order. Replacing `in development` did not make the
page claim release, because the structured data spells it `In development` and the
check reads case-insensitively. Replacing the note under the headline left the
footer saying it. **A mutation has to break the property, and `mutate` can only
tell you the file changed** — the rest is still a person's judgement, and mine was
wrong three times in twenty-eight.

**One of those wrong mutations found a real gap.** The page states what it is
three times: the note under the headline, the footer, and the `description` in the
structured data. Nothing required them to agree, and two of the three are places
nobody re-reads. A release would update the sentence a person sees and leave a
search result saying the software is unfinished. Now held, and proven by changing
every visible mention while leaving the JSON-LD, and the reverse.

**The hook earned itself on its first chance.** It refused the commit carrying
that guard, because the guard's own failure message had a run of spaces in it —
the whitespace check caught it, in a suite the old hook did not run. Yesterday
that commit would have gone out red, as one did.

## The guard that could only see the implausible version

**Decision.** Check the machinery, and say in the README what is actually
enforced.

`CoreHasNoHumanStrings` scans the model modules for string literals in Cyrillic,
Arabic, Han and Devanagari. That catches a *translated* string reaching a model —
the shape the rule breaks in when somebody is working in another language. It
cannot catch an English one, which in a project written in English is the version
that would actually happen.

And no check can. `ProviderFailure.diagnostic` is English on purpose: it goes to
the log while the interface shows a translated sentence in its place, and the
model modules hold thirty literals of three words or more, every one of them a
diagnostic. *"Profile not parsed"* and *"almost exhausted"* are the same shape to
a scanner and opposite in kind. A three-word rule would have refused all thirty.

So the third check takes the mechanism instead of the text. A label has to be
translated to be shown; translating goes through `Localization`; no model module
references it, `NSLocalizedString`, or `String(localized:)`. That is exact, it is
the path the rule actually erodes along, and it is true today.

**The README claimed more than was enforced.** "A test scans the sources to
enforce this, so a label cannot quietly move back into a model." It could — if it
were English, which it would be. The paragraph now says what each half catches
and states the diagnostic exception, which it had not mentioned at all.

**Proving it needed a mutation that compiles.** The first attempt put
`Localization` in a comment, and the scan strips comments on purpose — the guard
was right and the mutation was not. The second broke the build, which makes the
test command fail and `mutate` report a catch for the wrong reason: a mutation
must leave the thing buildable, or the check is being credited for the compiler's
work. A `private let` holding the word does both.

Five more guards audited alongside it — AppKit in the core, the app group's name,
a service name in lower case — all caught.

## The check that could not read the files it was about

**Decision.** Scan every text file kind, look for a team identifier in the form
it is typed in, and close the hole a conditional rule leaves.

Auditing the source-scanning guards found three things, each worse than the last.

**A conditional rule is defeated by removing its condition.**
`everyViewThatSetsDirectionAlsoSetsLocale` applies to a file that takes its
direction from the language. Writing `.rightToLeft` straight into a view makes it
stop applying — and the view then has a direction nobody chose and a locale
nobody set. Found by trying to break the rule and failing: the mutation took out
the trigger rather than the property, and the guard fell silent exactly as it
would for the real mistake. Nothing but the chart may write a direction in now.

**The personal-data scan read seven file kinds and not the four its own checks
are about.** The list was the extensions a leak had happened in: swift, py, md,
strings, yml, json, html. An Apple team identifier and a bundle identifier — the
subjects of two of the nine checks — live in `.entitlements`, `.plist` and
`.xcconfig`, and none were read. Nor was `.sh`, which is where a host address or
a token gets pasted. Widening it found one immediately, in `deploy.sh`, the file
the paths-into-other-projects check was written about: it named a directory on
the host to explain a pattern. The sentence did not need the path.

**And the team-identifier check looked in the wrong shape.** It matched ten
upper-case alphanumerics in front of `.group.` — a prefix inside a container
path. Where one is actually typed is `DEVELOPMENT_TEAM = …` in an xcconfig, and
`Signing.xcconfig` is tracked while `Signing.local.xcconfig` beside it is not:
pasting into the wrong one is a keystroke. Until the walk read `.xcconfig` at all
this could not have fired, so widening the walk and narrowing the pattern were
the same repair.

**Nine mutations besides, all caught** — a percentage built by hand, a percent
sign spelled into a catalogue, an orphan key, a surface not drawing the shared
row, AppKit in the core, a translated literal in a model, a model reaching for
`Localization`, the app group's name, a service name in lower case.

## The guard that never read the document it was named for

**Decision.** Extract the paths from the README instead of listing them.

`everyDocumentTheReadmePointsAtExists` held twelve paths and checked those files
existed. It never opened the README. So it passed with the README citing a
document that is not there — the exact thing its name promises to catch — and
would have passed with the README empty. Found by mutation: renaming a cited
document produced no failure.

It is two checks now, each true to its name. One takes every backticked token in
the README whose first segment is a real top-level entry here and requires the
file to exist. The other keeps the list, but asserts the README still *names*
those documents, which is the other direction and the one the plans' note went
missing in.

The filter matters: the README also quotes `.plist` as a kind of file,
`api.anthropic.com/api/oauth/usage` as a URL, and `prev/` as a directory on the
deploy host. Twenty-one tokens look like paths and seven of them are not paths in
this repository, so a naive extraction would have been noisy enough to be
switched off.

**The whole personal-data suite is now proven.** All nine checks broken on
purpose and each caught: an address outside the reserved domains, an account
identifier of the right shape, a key-shaped string and a JWT-shaped one, an
absolute path from one machine, the machine's own name, a routable address, a
foreign bundle prefix, a team identifier in both the shapes it takes. The
hostname one was proved by replacing the source of the name rather than writing
the real one to disk.

**And one false alarm of my own, caught before it was reported.** `grep` without
`-i` said the README no longer contains "all four sizes". It contains "All four
sizes", and the check that reads it is case-insensitive on purpose, for exactly
this reason.

## What seventy mutations found

**Decision.** The audit is finished. Recording the shape of what it caught,
because the shape repeats.

Around seventy mutations across every suite in the repository. **Five guards were
hollow.** Each had been written deliberately, reviewed, and believed for days.

- `theAppearancesAreTheOnesTheAppOffers` — required a radio with the right id.
  The radio is a pixel wide at zero opacity; the label is the control. Deleting
  the label left two appearances and a green check.
- `theChartUsesTheAppsColoursInTheAppsOrder` — read the legend and the order the
  palette hands slots out in, thoroughly, and never that `.chart .lN` is drawn in
  `--id-N`. The key under the drawing could describe a different drawing.
- `everyViewThatSetsDirectionAlsoSetsLocale` — conditional, and silent when the
  condition is removed. Writing a direction in makes the rule stop applying.
- `everyDocumentTheReadmePointsAtExists` — held twelve paths and never opened the
  README. It would have passed with the README empty.
- `noWidgetPrintsTheTimeTheEntryWasBuilt` — watched for one syntax, and the same
  wrong answer arrives by another road. The test *below it in the same file* says
  in words that a guard shaped like the last bug is not enough.

**Every one of the five is a source scanner, and not one behavioural test was
hollow.** A test that computes something and compares it cannot quietly examine
nothing; a scan that finds nothing looks exactly like a scan that found nothing
wrong. That is the whole difference, and it is worth knowing which kind a check
is before trusting it.

**Every one checked the half of the fact that was easy to reach.** The id is in
the markup and the label is three characters further. The legend is a row of dots
and the lines are a stylesheet away. The list of documents was in the test and
the README was a file away. None of that is visible from reading the test, which
is why reading tests does not find them.

Two more holes were scope rather than shape: the personal-data walk read seven
file kinds and not the four its own checks are about, and the team-identifier
pattern matched the form the value is stored in rather than the form it is typed
in. Widening the first found a real leak in `deploy.sh` immediately.

**And three of my own mutations were wrong** — changing a byte that did not
change the property, taking out a rule's trigger instead of its subject, breaking
the build so the compiler failed instead of the check. `mutate` can say the file
changed; whether the change means anything is still a person's judgement, and
mine was wrong once in twenty-three.

## The page a reader has enlarged the text on

**Decision.** Hold the layout at a raised minimum font size, and check it there.

A browser's minimum font size is one of the few accessibility controls people
genuinely use, and nothing here had ever rendered with one set. At 24 px the page
scrolled sideways on a phone: the appearance switch ran 87 px past a 320 px
screen, `~/.codex/sessions` had nowhere to break, and the window mock's badge was
wider than the window. `check-widths.sh` never saw any of it, because it rendered
at the default size only. It now runs its whole sweep twice.

Three repairs. The header wraps rather than overflowing — at the default size the
two halves sit on one line with room to spare, so nothing moved: rendered before
and after at 1440×3600 and the images were byte-identical. The path breaks
anywhere. And the mock clips rather than taking the page with it; it is
decorative, carries its own `aria-label` sentence, and nothing is clipped at any
size where it still reads as a window.

**The bar is 24, and it was briefly 32 on the strength of the wrong question.**
My probe asked whether the *page* scrolled sideways, and by that measure 32 was
clean. `check-widths.sh` asks whether any *element* runs past the edge, which is
stricter and better — clipped content is hidden content — and at 32 the mock's
staleness badge does. It cannot be made not to: a minimum font size is a floor
CSS may not go under, and a picture of a 322 px window with 32 px text inside it
does not exist. So 24, which is what a browser calls "very large" and the largest
size at which everything genuinely fits. The commit that set 32 shipped with the
width check failing, which the pre-commit hook does not run.

**And one of the three repairs is guarded and one is not.** The header wrap fails
the check when removed; the unbreakable path still fits at 24, so removing its
fix changes nothing the check can see. Recorded rather than papered over: raising
the bar to reach it would pin a layout that cannot hold.

**A CSS rule that changed nothing at all, first time.** The narrower label
padding was written into the earlier media block, ahead of the switch's own
rules; at equal specificity the later one wins. Measured the computed padding
rather than assuming, which is the only reason it was noticed.

## Nothing in the suite renders the page

**Decision.** The hook renders it when the commit touches it, and the one rule
the renderer cannot defend is pinned in the suite.

Yesterday's commit raising the width bar past what the page can hold went out
with that check failing. Everything ran: four hundred tests, the personal-data
floor, the whole hook. None of it renders the site — the suite reads the markup
as text, and a layout that does not hold is invisible to reading.

So `check-widths.sh` now runs from the hook, but only when `site/` is staged.
About five seconds against four for the suite, and a commit that touches no page
has no layout to break. A missing Chrome says so out loud and lets the commit
through: a check that quietly did not run is the failure this hook exists
against, and refusing a commit because a browser is not installed would be worse
than saying the layout went unexamined.

**And the rule the renderer cannot reach.** `~/.codex/sessions` has nowhere to
break, and at the 24 px bar it still fits — the size where it does not is one the
mock cannot hold either, so raising the bar to catch it would pin a layout that
cannot exist. Removing `overflow-wrap:anywhere` therefore changes nothing the
width check can see. It is pinned in the suite instead, with a second half that
fails if no code span holds a token long enough to need it, so the rule cannot
quietly become a property kept for nothing.

Both proven by breaking, and the hook proven by staging a page whose header no
longer wraps: it refused, and named the two widths and the element.

## The page on paper

**Decision.** Print in ink, not in whatever palette the reader was using.

A browser's print dialog has "Background graphics" off by default. The page's
colours are `light-dark()` pairs following `color-scheme`, so a reader in the
dark palette would have put near-white text onto white paper — nothing had ever
printed it to find out.

One line does most of the work: pinning `color-scheme: light` inside `@media
print` flips every token at once, which is the whole argument for having defined
them as pairs. The two `html:has(:checked)` rules have to be beaten alongside it,
or the reader's own choice survives onto the page. The appearance switch is
hidden — paper cannot offer three radio buttons — and everything else stays,
including the window mock: without background graphics its bars drop out and the
percentages beside them remain, which is the part worth reading. On paper it
comes out as a clean outlined window.

**The simulation was wrong before the fix was right.** Suppressing every
background to imitate the print dialog left the page still dark, because
`color-scheme: dark` paints the canvas itself and no background rule touches
that. Rather than model a browser more carefully, the page was made correct by
construction and then printed: dark palette chosen, backgrounds suppressed, read
back as a PDF. Both pages legible.

Zero pixels changed on screen, checked by rendering before and after. A test
holds the block, including the two rules it has to beat, because losing those
would leave the print stylesheet present and doing nothing for exactly the reader
it exists for.

## Correction: the print change is committed and not deployed

Written the same hour as the entry above it, because that entry would otherwise
read as though the page on the server had changed.

`deploy.sh` refused: *"does not answer on ssh — nothing was built, copied or
deployed"*. Its preflight check, added so that an unreachable host would be one
clear sentence rather than the first of eight timeouts, did exactly that.

The host is reachable in every other way. It answers ping, port 22 and port 443
both accept a connection, and `https://softcap.app/` serves 200 — the previous
version, correctly and completely. What fails is the SSH banner exchange, the
same symptom this log records against `github.com` two days ago: the connection
establishes, the client sends its version string, and nothing comes back.
Whatever is filtering SSH on this path has widened to include the droplet.
Deploys from here worked an hour ago.

So the state is: committed, pushed, tested, and not live. Nothing is broken and
nothing is half-shipped — the refusal is the design working. The change goes out
on the next run that finds ssh answering.

## Knowing the server is behind

**Decision.** `deploy.sh --status` — the one part of that script that needs no
ssh.

Two runs in a row could not deploy: the banner exchange to the droplet times out
while it answers ping, accepts connections on 22 and 443, and serves the site
perfectly. The deploy refused, which is right. But the repository then sits ahead
of the server and *nothing says so* — the drift has been visible only because
somebody happened to compare a digest by hand each time.

`--status` fetches each served file and compares it with the one here. Right now
it says exactly the truth: `index.html` differs, the other five match, the server
is not serving this checkout. It exits 1 on drift and on anything it could not
fetch, so it can gate as well as inform.

**Two small things it was written wrong first.** It recognised the SHA-256 of an
empty body to detect an unreachable URL — which works, because a body that did
not arrive digests like any other, and reads like a riddle. It asks curl for the
status code now. And it made a temporary directory to delete afterwards; it
writes into a fixed path the way `check-widths.sh` alongside it does, so a script
that runs unattended contains no delete with a variable in its path at all.

Both failure paths proven: the drift here, and every file answering 404 when
pointed at a domain that does not serve them.

**Still not deployed.** The print change from the previous entry is committed,
pushed, tested and waiting. Nothing is half-shipped.

## Two of three

**Decision.** Count the lock screen's shapes from the widget rather than from
memory.

The README said the phone offers "the two accessory shapes a lock screen
allows". A lock screen allows three: the circle, the rectangle, and the inline
one beside the clock. The widget draws two of them on purpose — inline has room
for a few words and would have to leave out either the figure or whose it is —
and the sentence turned a deliberate choice into a statement about iOS that is
not true.

Small, and the kind that matters here: it is in the one document a developer
reads before the code, and it is the sort of thing a reader who knows the
platform notices immediately. The count now comes from the widget's own
`supportedFamilies`, in both directions — offering the inline shape fails the
test as loudly as dropping the circle.

**A third run could not deploy.** The banner exchange to the droplet still times
out. `deploy.sh --status`, written for exactly this, says what is behind: the
print change and now this one wait, everything else on the server matches.

## Two hundred entries and nowhere to see them

**Decision.** `tools/decisions-index` — read the log and git, not a file that
would drift.

This log is two hundred and three entries and fifty-six thousand words. The
README says the way to find something is to search the headings, and there was
nowhere the headings could be seen together. The instruction was true and
unusable.

Not a generated index committed beside it: that drifts from the log the first
time one is appended without the other, which is the defect most of these entries
are about. The tool reads both each time it runs.

**Where a date comes from matters here.** Forty-two headings carry their own
(`## 2026-08-30 · …`), from when the log was written in that style; those are
believed, because they say when the decision was made. The rest are dated by the
commit that added them. Those two rules cover each other exactly: the early
entries were written in Russian and translated later, so git would date them to
the translation — and they are the ones carrying their own date. Checked: every
one of the two hundred and three comes out dated, thirty-five on the first day,
ninety-seven on the second, seventy-one on the third.

It refuses to print anything if it finds no headings, because a log whose format
has changed under it would otherwise produce an empty index that reads like an
empty log. Proven by changing `##` to `###`.

**A fourth run could not deploy.** The banner exchange to the droplet still times
out; `--status` says `index.html` is the one file behind.

## The phone app, looked at

**Decision.** Do not date a reading that does not exist.

The landing says "an iPhone app" and nobody had ever run one. `make build-ios`
succeeds, the app installs, launches, and stays up — checked with `simctl` alone,
so no simulator window opened on anybody's screen. Then a screenshot, which is
the part that mattered.

It came up with a fair empty state — *No accounts found*, and what to do about it
— and a timestamp above it. `lastUpdated` is set after every poll, including one
that found nothing, so the screen carried the current time over an empty list.
That reads as "these figures are current and there are none of them" rather than
"nobody is signed in", and it is the same shape as the two entries above it about
widgets printing the moment they were built. The Mac window in that state shows
its two sentences and no time. The phone does now too.

**Three of my own instruments were wrong on the way to it.**
`grep -c "BUILD SUCCEEDED"` returned zero on a build that succeeded, because grep
colours its own output and put escape codes inside the phrase — the failure this
log already records against a UDID. `sips -c` crops from the centre, not the top,
so the first screenshot of the header was a picture of the middle of an empty
screen. And the first screenshot was taken before the view had drawn, because the
loop written to wait did nothing at all: `for i in 1 2 3; do echo -n ""; done`
takes no time. `timeout 8 tail -f /dev/null` is a wait.

**A fifth run could not deploy.** The banner exchange still times out; the print
change is still the one file behind.

## `#if DEBUG` compiled to nothing

**Decision.** Define it in the Debug configuration, and abandon what led there.

The phone's list layout has never been rendered anywhere but an Xcode preview,
which is a window somebody has to open. The sample data for those previews is
right there in the file, so the plan was a launch argument that fills the model
with it — the populated screen could then be screenshotted in a simulator, with
no device, no sign-in and no Xcode.

**It does not work, and four attempts did not make it.** The samples were wiped
by `start()` polling an empty keychain; fixed. The argument never arrived,
because iOS reads `-key value` pairs off the command line into `UserDefaults` and
they never reach `CommandLine.arguments`; changed to a plain word. Still empty.
The whole attempt is reverted. The populated phone screen remains unrendered, and
saying so is better than leaving half a mechanism in the app for a picture nobody
got.

**What it did find is worth keeping.** Nothing in this project defined `DEBUG`.
Both configurations share one `Signing.xcconfig`, no `SWIFT_ACTIVE_COMPILATION_
CONDITIONS` existed anywhere, and a build in `Debug-iphonesimulator` is not by
itself a debug build. Every `#if DEBUG` compiled to nothing. Only two existed,
both written in the same hour as the discovery, so it had cost nothing yet — the
next one anybody wrote would have been absent from the build with no sign of it.

**Two instruments were wrong before the answer came from the app itself.**
`strings` on the built binary found neither the sample data nor `No accounts
found`, which is certainly in there — so it cannot answer questions about this
binary at all, and it was believed for one wrong conclusion first. Then the app
was made to log what it saw: `DEBUG is defined`, and an argument list holding
only the executable's path. That settled both questions in one line each.

**Deployed.** The print change from four entries ago went out this run: ssh
answered, and `--status` says the server is serving exactly this checkout.

## The plans, swept against the code

**Decision.** No change. Recorded because the plans' note says they are not a
reliable record of what was finished, and now says how far that was checked.

Two things the plans specify had been found missing months of work apart — a
shortcut with a settings field and nothing registering it, and the countdown's
tests. Nobody had swept the rest. Sixty-seven file paths and three hundred and
sixteen types, functions and test names, taken out of the three plans and looked
for in the code.

**Nothing was quietly dropped.** Seven paths and fifteen names are absent, and
every one is a rename, a move, or a design changed on purpose: `ThresholdNotifier`
became `ThresholdTracker`, the row moved into `StatusUI`, `SnapshotOrdering` moved
from `ProviderKit` to `Monitoring`, `formatRemainingCompact` became
`remainingCompact`, `Scope` became `WindowScope`, the four countdown tests exist
under names that describe what they assert, and `unregisterAll` was never needed
because `register` unregisters its own identifier first. Each rename is already in
this log.

**The sweep reported everything missing on its first run.** Three hundred and
sixteen of three hundred and sixteen — which is the shape of an answer that is
not an answer. The set of identifiers it compared against was empty, because the
`grep` building it had failed and an empty result reads exactly like a result
with nothing in it. It has a floor now: a hundred files and a thousand
identifiers, or it refuses to conclude. The second run read a hundred and
twenty-five files and five thousand two hundred and forty names.

That is the same failure this log has recorded more than thirty times, in the
tool written to check whether anything else had been missed.

## A test that passed all evening and failed at one in the morning

**Decision.** `events(for:now:)` takes no default moment.

The suite went red between two runs with nothing changed. `theBaselineSurvivesARebuild`
sets quiet hours of one o'clock to two and left `now` to the actual clock; it was
written before midnight, passed, was committed green and pushed — and failed once
the hour arrived. This log already says a test that fails once and passes twelve
times is worse than failing, and this is that with a timer on it.

The moment is required now. `AppModel` is the only caller in the app and has
always passed `Date()`, so it costs nothing there, and the trap cannot be written
again: anything deciding by the clock has to say which moment it means.
Forty-three call sites in the tests name theirs.

**The compiler cannot guard this.** Putting the default back compiles and breaks
nothing — it is a source-compatible change, and the first thing tried after the
fix was asking whether the build would fail, which proved nothing and was reported
as though it had. A test reads the signature instead.

**The sweep for others found none.** Every remaining `events(for:)` call runs on a
tracker with no quiet hours, where the clock decides nothing, and the two
deliberate quiet-hours tests were already passing an explicit moment. Two files
in the tests mention `Date()` and neither compares against one.

## Softcap updates itself, and not with Sparkle

**Decision.** The app checks GitHub once a day for a newer release, downloads
it, verifies it, replaces itself and restarts. All of it is ours; the standard
framework was not used.

**Why not Sparkle.** It brings its own window with its own strings, and those
follow the *system* language. Every other label in this app follows a switcher
that needs no restart — that was built deliberately and a test holds it. An
update window speaking a different language from the screen it was opened over
is a seam in the one place the app made a point of not having one, and it would
also be the project's first external dependency. Roughly four hundred lines of
our own was the price of not having either.

**What the checks are worth, said plainly.** Four refusals stand between a
release and an installed app: the bytes match what the release published, the
archive opens into a bundle, that bundle is Softcap at the version the release
claimed, and — for a build signed with a Developer ID — it is signed by the same
team.

The checksum arrives from the same origin as the file. It catches a truncated or
corrupted download. It does **not** catch a compromised GitHub, because whoever
could replace the archive could replace the sums beside it. What stands behind
that is TLS and the decision to trust GitHub with the release, which this project
already asks of anyone who downloads the disk image by hand.

The signature check is the one that would notice a swapped bundle, and it does
nothing at all for an ad-hoc build: an ad-hoc signature is regenerated on every
build and identifies nobody, so there is nothing to compare and the step passes.
Every published build is ad-hoc today.

This is written down because the interface cannot say it at that length, and
because somebody reading the code later would otherwise reasonably conclude that
more was checked than was.

**Cost, and the thing that pays for it.** These are the only checks there are.
`URLSession` does not mark a download with `com.apple.quarantine` the way a
browser does, so Gatekeeper never looks at what the updater installs. That
absence is the feature — it removes the "cannot be opened" dialog the README
apologises for — and it is exactly why nothing downstream will catch what these
four miss.

## The landing promised something the updater broke

**Decision.** The privacy sentence on the landing page now says what leaves the
machine instead of saying that nothing does.

It read: "Credentials stay in the keychain, never copied into preferences or
logs. No telemetry; nothing else leaves your Mac." A version check is a request
that leaves. It carries nothing about the reader — no identifier, no usage, no
account — but GitHub sees an address, and the sentence as written said that does
not happen.

It now says: "No telemetry. The only other request is a daily check for a new
version, and it can be switched off."

**What forced it.** `NothingElseLeavesYourMac.everyHostIsOneWeNamed` refuses any
host the sources name that its own list does not. Adding `api.github.com` and
`github.com` failed the suite, which is the whole reason that check exists — the
comment above it says so: "the point is not to catch a request; it is that adding
a host you have to name here is the moment to notice you are adding one."

**Cost.** The sentence is longer and less clean than the one it replaces. Quietly
keeping the old wording would have been the worse outcome by a distance: the
guard would have caught the host, and the page would have gone on making a claim
that had stopped being true.

## Every published build called itself 0.1

**Decision.** `CFBundleShortVersionString` is `$(MARKETING_VERSION)` on all four
targets, and `CFBundleVersion` is set at all.

`project.yml` wrote the version out as a literal on the app target while the
widget beside it took it from the build setting. The release workflow passes
`MARKETING_VERSION` on the command line, so the widget followed it and the app
did not: the two iOS targets declared no version at all, and `CFBundleVersion`
was set on none of the four — which is the bare `1` the About screen had been
showing.

**Why it cost nothing until now.** Nothing read the number. An updater reads it
to decide whether it is out of date, and would have been told yes forever.

**How it was confirmed.** By building with `MARKETING_VERSION=9.9.9` and reading
the value back out of the built bundle's `Info.plist` — which is exactly what the
workflow does. Believing the project file would have proved nothing: the file
already looked correct in the place somebody would think to check.

## A 404 is not a network failure

**Decision.** The release feed reads the answer's status before its body, and a
404 means there is nothing newer rather than that something went wrong.

GitHub answers 404 when a repository has never published a release. This one has
not, so every check made while the updater was being built came back that way,
and the screen said "GitHub could not be reached. Check the connection and try
again." over a connection that was working perfectly. Advice to go and fix the
wrong thing is worse than no advice.

It had a second symptom that looked unrelated: the screen said the last check was
"never" while a check had just run, because a failed check records no moment. One
cause, two complaints, and the second would have been chased on its own.

**Cost.** A second entry point on `ReleaseFeed` and three more tests. Anything
that is not 200 or 404 stays a failure and puts its status in the log, because a
rate limit and an outage look identical on screen and are worth telling apart
afterwards.

**How it was found.** By running the app and reading the screen. No test would
have caught it: every test had been handing the decoder a body and never a
status, so the status was the one thing nothing exercised.

## Two screens, one name

**Decision.** The settings screen called "Updates" is now "Polling and launch",
and a new one has the name.

It was about poll frequency, launch at login and hot keys — and its icon was a
circling arrow, which suits polling and never suited updating. Leaving it would
have put app updates under *About* while a screen called Updates meant something
else, which is a confusion this feature introduced and should therefore resolve.

## Every screen lines up with its own heading

**Decision.** The six settings screens built from a grouped `Form` cancel the
inset it adds, so their content starts where their heading does.

A grouped `Form` insets its rows by twenty points of its own, on top of the
padding the detail area already applies. Accounts and Statistics are built
without one and their content sat directly under the heading; the other six were
indented from it by that twenty.

**Why it survived this long.** Nobody notices one screen at a time. It is the
first thing you see when two are put side by side, and that is how it was found —
by comparing a new screen against an old one.

**Cancelled, rather than moving the headings across.** The content is what a
screen is, and the wider boxes are the ones the window has room for. The twenty
is measured rather than assumed: on a screenshot of the Notifications screen the
heading sat 207.5 pt from the window's edge and the first row's box at 227.5 pt.
A number guessed here would have misaligned every screen by however wrong it was,
in the direction nobody would think to look.

**Cost.** A modifier every `Form`-based screen has to remember to call, and a
test that reads the sources to make sure it does — the compiler cannot see this,
because a screen that forgets it builds, runs, and looks almost right.

## The signature check checked nothing

**Decision.** `SecStaticCodeCheckValidity` runs before the signing identity is
read, and an arriving bundle whose signature no longer covers its code is
refused.

The entry above — "Softcap updates itself, and not with Sparkle" — describes
four refusals standing between a release and an installed app, and says the
signature check "is the one that would notice a swapped bundle". It would not
have. It called `SecCodeCopySigningInformation`, which parses the signature blob
and reports what it says: a bundle whose executable has been replaced still
names the team that signed the original. Reading an identity is not checking it.

**How it was proven.** A bundle was signed, its executable patched afterwards,
re-zipped, and the checksum computed from the patched archive — which is not
cheating: whoever can publish the archive publishes the sums beside it, so a
matching checksum is what an attacker would always have. Before the fix that
bundle installed itself. The test does exactly that, and deleting the check
makes it fail on the line that says the installed app was replaced.

**Cost.** Ad-hoc builds are now covered too, which the earlier entry said they
could not be. That was also wrong: an ad-hoc signature identifies nobody but it
still seals the bundle it was made from, and `codesign --verify` — which the
release workflow already runs — asks exactly this question. Only the *identity*
half is useless for ad-hoc; the *integrity* half was available all along and was
not being asked.

## A review of the updater, and what a review is worth

**Decision.** The whole feature was read back before it was pushed, and fifteen
findings were acted on.

Six were things no test could have caught because no test existed for them: a
signature check that checked nothing, a download that handed back the body of a
404 as though it were the archive, checksums that could not be fetched being
reported to the reader as tampering, a checksum file with Windows line endings
parsing as nothing at all — Swift counts `\r\n` as one Character, so splitting on
`"\n"` never matched it — a release compared only after its files were demanded,
and an archive whose bundle was chosen by whatever order the file system offered.

Two were guards that had stopped guarding. `CoreHasNoHumanStrings` held a list of
the six modules that existed when it was written, so `Updates` escaped the rule
CLAUDE.md names it as enforcing; the list is now of what is exempt, because a
list of the covered has to be edited to stay true and a list of the exempt has to
be edited to become false. And `CoreStaysPortable` only ever read import lines,
so it passed over a module that could not have compiled for iOS at all — `Process`
is absent from that platform and `SecStaticCode` is in the macOS SDK alone, while
`Security` itself is on both and gives an import check nothing to see.

One was the feature contradicting three documents at once: `checkIfDue` had a
single call site, the launch, so a menu bar app that starts at login and never
quits checked once and never again, while the README, the landing page and this
log all said once a day.

**Cost.** A day's work after the feature was already written, twenty-two tests
added, and several entries above this one that are now partly wrong. They are
left as they were; the corrections are here.

## Correction: the iOS targets did declare a version

**Decision.** This corrects "Every published build called itself 0.1" above.

That entry says "the two iOS targets declared no version at all". That is true of
`project.yml` and false of `iOS/Info.plist` and `iOSWidget/Info.plist`, which are
generated from it and were checked in carrying `1.0` and build `1`. Pointing them
at `$(MARKETING_VERSION)` therefore did not fill a gap — it moved a marketing
version and a build number backwards to `0.1`, which the App Store refuses
outright.

The build number is `$(CURRENT_PROJECT_VERSION)` again on every target, the
release workflow passes the run number so two builds of one marketing version
stay distinguishable, and the iOS pair keeps its own `1.0`.

**What let it through.** The guard written alongside that change was
`contains("CFBundleVersion:")` — true for any value at all, including the wrong
one it was written immediately after introducing. It now reads what each target
declares, and a second test holds the phone's version to its own.

## The download follows a redirect the host list cannot see

**Decision.** Recorded rather than fixed.

`NothingElseLeavesYourMac.everyHostIsOneWeNamed` scans the sources for host names
and refuses any it does not know. A release asset is fetched from
`github.com/.../releases/download/...`, which answers with a redirect to a
GitHub-owned asset host — `objects.githubusercontent.com` at the time of writing,
lately `release-assets.githubusercontent.com`. That name appears in no source
file, so the scan cannot see it, and `DownloadDelegate` implements no
`willPerformHTTPRedirection`, so the chain is followed as given.

The entry above leans on that check — "adding a host you have to name here is the
moment to notice you are adding one" — and for a redirect target that moment
never comes. It is written down here instead, which is the only place it can be.

**Why not refuse redirects.** Because the download would then not work: GitHub
serves every release asset this way, and the redirect target is not a stable name
to pin. What is being trusted is GitHub, which is the same thing the checksums
are worth and the same thing anyone downloading the disk image by hand already
trusts.

## The history is one commit

**Decision.** Every commit before this one was collapsed into it. The bundles
holding the old history stay on the author's machine and are not published.

**Why.** Three sweeps for private data — one on 31 August, two on 8 September —
each found something the sweep before it had missed, and every time the finding
sat where the working tree could not show it: a commit message, an index frozen
in a linked worktree, an unreachable object still in the pack. The eight checks
in `NoPersonalDataInTheRepository` read files. A value that reached the history
and then left the working tree passes all eight of them for ever.

Collapsing the history removes the class rather than the instance. There is no
old blob to search, no message to grep, no worktree index pinning a state from
before a cleanup. What the log recorded is prose in this file, and none of it is
lost.

**Cost.** `git blame` and `git log` now answer with one commit and one date, so
the reason behind a line has to be found here rather than beside it. Bisecting is
gone. The order in which things were learnt survives only as the order of these
entries — which is the standing reason they are never rewritten.
