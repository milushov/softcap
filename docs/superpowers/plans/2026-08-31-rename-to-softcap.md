# Rename StatusChecker to Softcap — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the product, its four bundle identifiers, its app group and its
widget kinds from StatusChecker to Softcap, leaving no working feature behind.

**Architecture:** The rename is mechanical but crosses four Xcode targets, a
Swift package, ten translation catalogues and the documentation. It is ordered so
that every task ends on a green build or a green test run: the identifiers that
must change together — the app group in two entitlements files and in
`SharedStore.baseGroup` — change inside one task, never across two.

**Tech Stack:** Swift 6, SwiftUI, WidgetKit, XcodeGen, Swift Testing, `make`.

## Global Constraints

- Documentation, specs and code comments are written in **English**. When editing
  an existing document, translate it rather than mixing languages.
- `Packages/Core` holds no strings meant for a person. Enforced by
  `CoreHasNoHumanStrings`, which scans `ProviderKit`, `Preferences`,
  `ClaudeProvider`, `CodexProvider`, `Credentials`, `Monitoring` — not `StatusUI`.
- Adding or changing a UI string means changing all ten catalogues. Key sets and
  placeholders are checked by `LocalizationCatalog`.
- Every non-obvious decision goes to `docs/DECISIONS.md` — what, why, what it
  cost. Entries are never rewritten.
- Never delete with `rm`. Use `~/.claude/bin/ctrash <literal path>`.
- New identifiers, fixed for the whole plan:
  - macOS app `app.softcap.Softcap`
  - macOS widget `app.softcap.Softcap.widget`
  - iOS app `app.softcap.Softcap.ios`
  - iOS widget `app.softcap.Softcap.ios.widget`
  - app group `group.app.softcap` (macOS entitlement carries
    `$(TeamIdentifierPrefix)` in front of it, iOS does not)
  - macOS widget kind `app.softcap.Softcap.limits`
  - iOS widget kind `app.softcap.Softcap.ios.limits`
- **The Keychain service name does not change.** `CredentialStore.ownService`
  stays `"StatusChecker-accounts"`. Accounts accumulated from the CLI are the one
  piece of user data that does not come back on its own, and Keychain access is
  bound to the code signature, not to the bundle identifier — so leaving the
  string alone costs nothing and loses nothing.

---

### Task 1: The ten translation catalogues

Three lines in each catalogue name the app: a header comment and two strings.
The key is the English phrase, so the key changes too — in all ten files at once,
or `LocalizationCatalog` fails on mismatched key sets.

The header comment is in Russian in all ten files, against the documentation
rule. It is rewritten here because this task already opens every one of them.

**Files:**
- Modify: `Packages/Core/Sources/StatusUI/Resources/{en,ru,es,fr,ar,bn,hi,id,pt-BR,zh-Hans}.lproj/Localizable.strings`
- Test: `Packages/Core/Tests/StatusUITests/LocalizationTests.swift` (exists, unchanged)

**Interfaces:**
- Consumes: nothing.
- Produces: the keys `"Quit Softcap"` and `"Open Softcap to load data"`, used by
  `App/StatusItemController.swift` and `Widget/LimitsWidgetView.swift` in Task 3.

- [ ] **Step 1: Confirm the tests are green before touching anything**

```bash
make test
```

Expected: `Test run with 180 tests in 10 suites passed` (the count grows as other
work lands; what matters is that it passes).

- [ ] **Step 2: Replace the name in all ten catalogues**

```bash
cd <repo>/.claude/worktrees/rename-softcap
for f in Packages/Core/Sources/StatusUI/Resources/*.lproj/Localizable.strings; do
  LC_ALL=C sed -i '' 's/StatusChecker/Softcap/g' "$f"
done
```

- [ ] **Step 3: Put the header comment into English**

```bash
cd <repo>/.claude/worktrees/rename-softcap
for f in Packages/Core/Sources/StatusUI/Resources/*.lproj/Localizable.strings; do
  LC_ALL=C sed -i '' '1s|.*|/* Softcap — interface strings. The key is the English text. */|' "$f"
done
```

- [ ] **Step 4: Check that every catalogue changed the same way**

```bash
grep -c "Softcap" Packages/Core/Sources/StatusUI/Resources/*.lproj/Localizable.strings
grep -rn "StatusChecker" Packages/Core/Sources/StatusUI/Resources/ || echo "clean"
```

Expected: every file reports `3`, and the second command prints `clean`.

- [ ] **Step 5: Run the tests**

```bash
make test
```

Expected: PASS. `everyLanguageCoversAllKeys` is the one that would catch a
catalogue left behind.

- [ ] **Step 6: Commit**

```bash
git add Packages/Core/Sources/StatusUI/Resources
git commit -m "Rename the app in the ten catalogues"
```

---

### Task 2: Core identifiers that carry no data

Logger subsystems and a dispatch queue label. None of them is persisted, so they
can move before the bundle identifier does. The app group is deliberately **not**
here — it changes in Task 3, together with the entitlements that grant it.

**Files:**
- Modify: `Packages/Core/Sources/StatusUI/Localization.swift:66`
- Modify: `Packages/Core/Sources/StatusUI/SharedSnapshot.swift:45`
- Modify: `Packages/Core/Sources/CodexProvider/SessionWatcher.swift:24`
- Modify: `Packages/Core/Sources/Credentials/CredentialStore.swift:55` (comment only)

**Interfaces:**
- Consumes: nothing.
- Produces: nothing other tasks call. `SharedStore.baseGroup` keeps its current
  value until Task 3.

- [ ] **Step 1: Move the three identifiers**

```bash
cd <repo>/.claude/worktrees/rename-softcap
sed -i '' 's|subsystem: "dev.example.StatusChecker"|subsystem: "app.softcap.Softcap"|' \
  Packages/Core/Sources/StatusUI/Localization.swift \
  Packages/Core/Sources/StatusUI/SharedSnapshot.swift
sed -i '' 's|"dev.example.StatusChecker.codex-watch"|"app.softcap.Softcap.codex-watch"|' \
  Packages/Core/Sources/CodexProvider/SessionWatcher.swift
```

- [ ] **Step 2: Say in the code why the Keychain service keeps the old name**

Replace line 55 of `Packages/Core/Sources/Credentials/CredentialStore.swift`:

```swift
    /// Deliberately still the old name after the rename to Softcap. Keychain
    /// access is bound to the code signature, not to the bundle identifier, so
    /// the string can stay — and accounts gathered from the CLI are the one
    /// thing here that does not come back by itself.
    public static let ownService = "StatusChecker-accounts"
```

- [ ] **Step 3: Run the tests**

```bash
make test
```

Expected: PASS, unchanged count.

- [ ] **Step 4: Commit**

```bash
git add Packages/Core/Sources
git commit -m "Core: log subsystems and the queue label follow the new name"
```

---

### Task 3: The macOS app and widget

The largest task, and the one that cannot be split: the app group name lives in
two entitlements files and in `SharedStore.baseGroup`, and a build where those
three disagree has a widget that silently reads an empty container.

**Files:**
- Rename: `App/StatusChecker.entitlements` → `App/Softcap.entitlements`
- Rename: `App/StatusCheckerApp.swift` → `App/SoftcapApp.swift`
- Rename: `Widget/StatusCheckerWidget.entitlements` → `Widget/SoftcapWidget.entitlements`
- Modify: `Packages/Core/Sources/StatusUI/SharedSnapshot.swift:50`
- Modify: `Widget/StatusWidget.swift:34,40`
- Modify: `Widget/LimitsWidgetView.swift:147`
- Modify: `App/StatusItemController.swift:164`
- Modify: `App/AppModel.swift:282`
- Modify: `project.yml:1,17,27,31,33,44,62,70,78,79`
- Modify: `Makefile:20,25`
- Modify: `.gitignore:6`

**Interfaces:**
- Consumes: `"Quit Softcap"` and `"Open Softcap to load data"` from Task 1.
- Produces: bundle identifier `app.softcap.Softcap`, app group `group.app.softcap`,
  widget kind `app.softcap.Softcap.limits`. Task 4 mirrors these on iOS.

- [ ] **Step 1: Rename the three files under git**

```bash
cd <repo>/.claude/worktrees/rename-softcap
git mv App/StatusChecker.entitlements App/Softcap.entitlements
git mv App/StatusCheckerApp.swift App/SoftcapApp.swift
git mv Widget/StatusCheckerWidget.entitlements Widget/SoftcapWidget.entitlements
```

- [ ] **Step 2: Move the app group in all three places at once**

```bash
cd <repo>/.claude/worktrees/rename-softcap
sed -i '' 's|group\.dev\.example\.StatusChecker|group.app.softcap|' \
  App/Softcap.entitlements Widget/SoftcapWidget.entitlements \
  Packages/Core/Sources/StatusUI/SharedSnapshot.swift
grep -rn "group.app.softcap" App/Softcap.entitlements Widget/SoftcapWidget.entitlements Packages/Core/Sources/StatusUI/SharedSnapshot.swift
```

Expected: three hits, one per file. The macOS entitlements keep
`$(TeamIdentifierPrefix)` in front; `SharedStore` adds the prefix at runtime by
reading its own entitlement, so its constant is the bare name.

- [ ] **Step 3: Move the remaining names in the app and widget sources**

```bash
cd <repo>/.claude/worktrees/rename-softcap
sed -i '' 's/StatusCheckerWidgetBundle/SoftcapWidgetBundle/; s|"dev.example.StatusChecker.limits"|"app.softcap.Softcap.limits"|' Widget/StatusWidget.swift
sed -i '' 's/Open StatusChecker to load data/Open Softcap to load data/' Widget/LimitsWidgetView.swift
sed -i '' 's/Quit StatusChecker/Quit Softcap/' App/StatusItemController.swift
sed -i '' 's/StatusChecker: notification not delivered/Softcap: notification not delivered/' App/AppModel.swift
sed -i '' 's/struct StatusCheckerApp: App/struct SoftcapApp: App/' App/SoftcapApp.swift
```

- [ ] **Step 4: Move the macOS half of `project.yml`**

Apply these exact replacements in `project.yml`:

| Line | From | To |
|---|---|---|
| 1 | `name: StatusChecker` | `name: Softcap` |
| 3 | `bundleIdPrefix: dev.example` | `bundleIdPrefix: app.softcap` |
| 17 | `  StatusChecker:` | `  Softcap:` |
| 27 | `CFBundleName: StatusChecker` | `CFBundleName: Softcap` |
| 31 | `PRODUCT_BUNDLE_IDENTIFIER: dev.example.StatusChecker` | `PRODUCT_BUNDLE_IDENTIFIER: app.softcap.Softcap` |
| 33 | `CODE_SIGN_ENTITLEMENTS: App/StatusChecker.entitlements` | `CODE_SIGN_ENTITLEMENTS: App/Softcap.entitlements` |
| 44 | `      - target: StatusCheckerWidget` | `      - target: SoftcapWidget` |
| 62 | `  StatusCheckerWidget:` | `  SoftcapWidget:` |
| 70 | `CFBundleDisplayName: StatusChecker` | `CFBundleDisplayName: Softcap` |
| 78 | `PRODUCT_BUNDLE_IDENTIFIER: dev.example.StatusChecker.widget` | `PRODUCT_BUNDLE_IDENTIFIER: app.softcap.Softcap.widget` |
| 79 | `CODE_SIGN_ENTITLEMENTS: Widget/StatusCheckerWidget.entitlements` | `CODE_SIGN_ENTITLEMENTS: Widget/SoftcapWidget.entitlements` |

- [ ] **Step 5: Move the build files**

```bash
cd <repo>/.claude/worktrees/rename-softcap
sed -i '' 's/StatusChecker\.xcodeproj/Softcap.xcodeproj/g; s/-scheme StatusChecker /-scheme Softcap /; s|Debug/StatusChecker\.app|Debug/Softcap.app|' Makefile
sed -i '' 's|^StatusChecker\.xcodeproj/|Softcap.xcodeproj/|' .gitignore
```

- [ ] **Step 6: Quarantine the old generated project**

The old `.xcodeproj` is ignored by git but still on disk, and `xcodegen` writes a
new one beside it.

```bash
~/.claude/bin/ctrash <repo>/.claude/worktrees/rename-softcap/StatusChecker.xcodeproj
```

- [ ] **Step 7: Build**

```bash
make build
```

Expected: `** BUILD SUCCEEDED **`, and the product is now
`build/Build/Products/Debug/Softcap.app`.

- [ ] **Step 8: Check the identifiers in the built bundle**

```bash
cd <repo>/.claude/worktrees/rename-softcap
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" build/Build/Products/Debug/Softcap.app/Contents/Info.plist
codesign -d --entitlements - --xml build/Build/Products/Debug/Softcap.app/Contents/PlugIns/SoftcapWidget.appex 2>/dev/null | tail -1
```

Expected: `app.softcap.Softcap`, and an entitlements blob holding
`app-sandbox`, `get-task-allow` and a group ending in `group.app.softcap`.

- [ ] **Step 9: Check that the widget registers and the channel carries data**

```bash
cd <repo>/.claude/worktrees/rename-softcap
pkill -x StatusChecker; pkill -x Softcap; sleep 1
open build/Build/Products/Debug/Softcap.app; sleep 10
pluginkit -mAvvv -i app.softcap.Softcap.widget | grep -E "Path =|app\.softcap"
ls -l ~/Library/Group\ Containers/*group.app.softcap/snapshot.json
```

Expected: the extension is listed, and `snapshot.json` exists with a timestamp
from the last few seconds. An empty `pluginkit` result means the sandbox
entitlement or the group name did not survive the rename.

- [ ] **Step 10: Run the tests and commit**

```bash
make test
git add -A App Widget project.yml Makefile .gitignore Packages/Core/Sources/StatusUI/SharedSnapshot.swift
git commit -m "The macOS app and widget become Softcap"
```

---

### Task 4: The iOS app and widget

Mirrors Task 3. The iOS app group carries no team prefix.

**Files:**
- Rename: `iOS/StatusCheckeriOSApp.swift` → `iOS/SoftcapiOSApp.swift`
- Rename: `iOS/StatusCheckeriOS.entitlements` → `iOS/SoftcapiOS.entitlements`
- Rename: `iOSWidget/StatusCheckeriOSWidget.entitlements` → `iOSWidget/SoftcapiOSWidget.entitlements`
- Modify: `iOSWidget/PhoneWidget.swift:40`
- Modify: `project.yml:93,103,111,116,121,136,145,150,154`
- Modify: `Makefile:33,48,49`

**Interfaces:**
- Consumes: `group.app.softcap` from Task 3 — the same group, so the phone app
  and the Mac app would share a container if they ever ran on one machine.
- Produces: bundle identifier `app.softcap.Softcap.ios`.

- [ ] **Step 1: Rename the files under git**

```bash
cd <repo>/.claude/worktrees/rename-softcap
git mv iOS/StatusCheckeriOSApp.swift iOS/SoftcapiOSApp.swift
git mv iOS/StatusCheckeriOS.entitlements iOS/SoftcapiOS.entitlements
git mv iOSWidget/StatusCheckeriOSWidget.entitlements iOSWidget/SoftcapiOSWidget.entitlements
```

- [ ] **Step 2: Move the names inside the iOS sources**

```bash
cd <repo>/.claude/worktrees/rename-softcap
sed -i '' 's|group\.dev\.example\.StatusChecker|group.app.softcap|' \
  iOS/SoftcapiOS.entitlements iOSWidget/SoftcapiOSWidget.entitlements
sed -i '' 's/struct StatusCheckeriOSApp: App/struct SoftcapiOSApp: App/' iOS/SoftcapiOSApp.swift
sed -i '' 's|"dev.example.StatusChecker.ios.limits"|"app.softcap.Softcap.ios.limits"|' iOSWidget/PhoneWidget.swift
```

- [ ] **Step 3: Move the iOS half of `project.yml`**

| Line | From | To |
|---|---|---|
| 93 | `  StatusCheckeriOS:` | `  SoftcapiOS:` |
| 103 | `CFBundleDisplayName: StatusChecker` | `CFBundleDisplayName: Softcap` |
| 111 | `PRODUCT_BUNDLE_IDENTIFIER: dev.example.StatusChecker.ios` | `PRODUCT_BUNDLE_IDENTIFIER: app.softcap.Softcap.ios` |
| 116 | `CODE_SIGN_ENTITLEMENTS: iOS/StatusCheckeriOS.entitlements` | `CODE_SIGN_ENTITLEMENTS: iOS/SoftcapiOS.entitlements` |
| 121 | `      - target: StatusCheckeriOSWidget` | `      - target: SoftcapiOSWidget` |
| 136 | `  StatusCheckeriOSWidget:` | `  SoftcapiOSWidget:` |
| 145 | `CFBundleDisplayName: StatusChecker` | `CFBundleDisplayName: Softcap` |
| 150 | `PRODUCT_BUNDLE_IDENTIFIER: dev.example.StatusChecker.ios.widget` | `PRODUCT_BUNDLE_IDENTIFIER: app.softcap.Softcap.ios.widget` |
| 154 | `CODE_SIGN_ENTITLEMENTS: iOSWidget/StatusCheckeriOSWidget.entitlements` | `CODE_SIGN_ENTITLEMENTS: iOSWidget/SoftcapiOSWidget.entitlements` |

- [ ] **Step 4: Move the iOS lines in the Makefile**

```bash
cd <repo>/.claude/worktrees/rename-softcap
sed -i '' 's/-scheme StatusCheckeriOS /-scheme SoftcapiOS /; s|Debug-iphonesimulator/StatusCheckeriOS\.app|Debug-iphonesimulator/SoftcapiOS.app|; s|dev\.example\.StatusChecker\.ios|app.softcap.Softcap.ios|' Makefile
```

- [ ] **Step 5: Build for the simulator**

```bash
make build-ios
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add -A iOS iOSWidget project.yml Makefile
git commit -m "The iOS app and widget become Softcap"
```

---

### Task 5: The paths a user is shown, and the documentation

The About pane prints the settings path, and it is now wrong: the preferences
file follows the bundle identifier.

**Files:**
- Modify: `App/Settings/AboutPane.swift:30`
- Modify: `App/LoginController.swift:23`
- Modify: `README.md:1,9,79,81`
- Modify: `CLAUDE.md:1`
- Modify: `docs/design/settings-screen.html:467`

**Interfaces:**
- Consumes: the bundle identifier from Task 3.
- Produces: nothing.

- [ ] **Step 1: Move the shown path and the last logger**

```bash
cd <repo>/.claude/worktrees/rename-softcap
sed -i '' 's|~/Library/Preferences/dev.example.StatusChecker.plist|~/Library/Preferences/app.softcap.Softcap.plist|' \
  App/Settings/AboutPane.swift docs/design/settings-screen.html README.md
sed -i '' 's|subsystem: "dev.example.StatusChecker"|subsystem: "app.softcap.Softcap"|' App/LoginController.swift
```

- [ ] **Step 2: Move the name through the documents**

```bash
cd <repo>/.claude/worktrees/rename-softcap
sed -i '' 's/StatusChecker\.app/Softcap.app/g; s/^# StatusChecker$/# Softcap/' README.md
sed -i '' 's/^# StatusChecker — project rules$/# Softcap — project rules/' CLAUDE.md
```

Leave `StatusChecker-accounts` in `README.md:81` alone — that name really did
stay, and Task 2 explains why in the code. Add the reason to the README line so a
reader is not left guessing:

```markdown
Accounts the app gathered itself are in the Keychain under the service
`StatusChecker-accounts` — the old name, kept through the rename so that nothing
already stored is lost.
```

- [ ] **Step 3: Check nothing was missed outside `docs/DECISIONS.md`**

```bash
cd <repo>/.claude/worktrees/rename-softcap
grep -rIn "StatusChecker" --exclude-dir=.git --exclude-dir=build --exclude-dir=build-ios --exclude-dir=.build . \
  | grep -v "^docs/DECISIONS.md" | grep -v "^docs/superpowers/" | grep -v "StatusChecker-accounts"
```

Expected: no output. `docs/DECISIONS.md` and the old plans and specs keep the old
name on purpose — they are a record of what happened, and entries are never
rewritten.

- [ ] **Step 4: Commit**

```bash
git add App README.md CLAUDE.md docs/design/settings-screen.html
git commit -m "The shown paths and the documents follow the new name"
```

---

### Task 6: Clear the old state, and check the whole thing works

The old identifier leaves three things on disk. None of them breaks anything, and
all three would confuse the next person to look.

**Files:**
- Create: an entry at the end of `docs/DECISIONS.md`

**Interfaces:**
- Consumes: everything above.
- Produces: nothing.

- [ ] **Step 1: Quarantine what the old identifier left behind**

```bash
pkill -x StatusChecker; pkill -x Softcap; sleep 1
~/.claude/bin/ctrash \
  ~/Library/Preferences/dev.example.StatusChecker.plist \
  ~/Library/Application\ Support/dev.example.StatusChecker
```

The old group container is left where it is: it sits under
`~/Library/Group Containers/` with a system-written metadata file, and removing
it by hand is not worth the risk. Beside a regenerable `snapshot.json` it also
holds `history.json`, an accumulated record from unmerged work in the other
checkout that still targets the old group name — merging this rename would
strand it.

- [ ] **Step 2: Build, test, and run**

```bash
cd <repo>/.claude/worktrees/rename-softcap
make test
make build
open build/Build/Products/Debug/Softcap.app; sleep 10
```

Expected: tests pass, build succeeds, the gauge appears in the menu bar.

- [ ] **Step 3: Check every renamed identifier at runtime**

```bash
cd <repo>/.claude/worktrees/rename-softcap
lsappinfo info -only ApplicationType "$(lsappinfo find bundleid=app.softcap.Softcap)"
pluginkit -mAvvv -i app.softcap.Softcap.widget | grep "Path ="
ls -l ~/Library/Group\ Containers/*group.app.softcap/snapshot.json
ls ~/Library/Preferences/app.softcap.Softcap.plist
```

Expected: `"UIElement"`; the widget's path inside `Softcap.app`; a fresh
`snapshot.json`; and a preferences file that the app has just created.

- [ ] **Step 4: Check the settings window still reaches ⌘⇥**

Open the menu bar icon, press **Settings…**, then:

```bash
lsappinfo info -only ApplicationType "$(lsappinfo find bundleid=app.softcap.Softcap)"
```

Expected: `"Foreground"` while the window is open, `"UIElement"` again after it
closes. This is the one behaviour a bundle identifier change could plausibly
break, because launch-at-login and the activation policy both key off it.

- [ ] **Step 5: Re-enable launch at login and re-add the widget**

Both were registered against the old identifier and are now forgotten. In
Settings → Updates and launch, switch launch at login off and on. Then
right-click the desktop → Edit Widgets → Softcap, and place the widget again.

- [ ] **Step 6: Write the decision entry**

Append to `docs/DECISIONS.md`, following the house format — what was decided, why,
what it cost. Cover: the identifiers moved to `app.softcap.*` while the Keychain
service deliberately did not; settings, launch-at-login and the placed widget
were dropped rather than migrated, because there is exactly one installation and
migration code written now would be carried forever; the old preferences file and
Application Support folder went to quarantine, and the old group container was
left alone.

- [ ] **Step 7: Commit**

```bash
git add docs/DECISIONS.md
git commit -m "Journal: what the rename to Softcap cost"
```

---

## Notes for whoever runs this

**A second session works in this repository.** Through the evening of
2026-08-30 another agent committed into the same branch, several times sweeping
in-progress files from this session into its own commits. Before each task, run
`git status --short` and stage only the files the task names. Do not use
`git commit -a`.

**The build regenerates `project.yml`'s outputs.** `Widget/Info.plist`,
`iOS/Info.plist` and `iOSWidget/Info.plist` are written by XcodeGen from
`project.yml`, so they change on the first `make build` after Task 3 and must be
committed with it — `git add -A` inside the named directories covers this.

**The app group needs no portal registration.** Verified on 2026-08-30: on macOS,
manual signing with a real team certificate is enough, and the Xcode account on
this machine has a stale token. `-allowProvisioningUpdates` does nothing here.
