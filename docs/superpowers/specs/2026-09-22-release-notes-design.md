# Every release lists what changed — design

**Date:** 2026-09-22
**Status:** approved, implemented 2026-09-22

## The problem

Every push to `main` that touches anything but documentation produces a GitHub
release numbered `0.1.<run>`, and the body of every one of them says the same
three things: which commit it was built from, how to install it, and the
checksums. Nothing says what changed. The releases page reads as a list of
numbers, and the Updates screen in the app — which shows this same body in a
box a few lines tall — shows a checksum to somebody deciding whether to update.

Two things follow from the way the pipeline works. The commit subjects in this
repository are already one-sentence descriptions of each change, written for a
reader ("Let the staleness badge shrink before it leaves the screen"), so the
list exists and only has to be read out. And roughly half of the recent releases
were rebuilds: a push that changed the site, the store listing or a tool
produced a new version that differed from the last in nothing but its number —
and the in-app updater offered it to everyone.

## What was decided

1. **The release body opens with the subjects of the commits that changed the
   app since the previous release**, oldest first. What changed the app is
   decided by what a commit touched, not by how its subject reads.
2. **A push that changed nothing in the app publishes nothing.** The tests still
   run; the build and the release are skipped. A run started by hand
   (`workflow_dispatch`) always builds, and its notes say when it is a rebuild.
3. One list of paths — *what the disk image is made of* — answers both
   questions, and it lives in one tool the workflow calls twice.

## What a release reads like

```markdown
- Spell the chart's dates and the window's own title in the app's language
- Write the store listing ten times, and photograph the app in each language

Built from `0cd2f8c` on 2026-09-20 — [everything since 0.1.31](https://github.com/milushov/softcap/compare/v0.1.31...v0.1.32).

**Install** — open the disk image and drag Softcap to Applications.

### Checksums
…
```

The list comes first because the app's Updates screen shows the top of the
body. There is no heading over it: the in-app renderer interprets inline
Markdown only and would print `###` literally, the screen already says
"Version X is available." above the text, and on GitHub the release's title is
the version.

A rebuild asked for by hand, with nothing new in the app:

```markdown
Nothing in the app changed since 0.1.36 — the same sources, built again.

Built from `2b256f0` on 2026-09-22 — [everything since 0.1.36](…/compare/v0.1.36...v0.1.37).
```

A repository with no release tag at all (a fresh fork) gets the `Built from`
line alone, and is built.

The `Install` paragraph, the ad-hoc-signing paragraph and the checksums follow
exactly as they do today.

### What is listed

A commit is listed when it is not a merge and touched at least one of:

    App/                 Packages/  (except Packages/Core/Tests/)
    Widget/              Resources/
    project.yml          Signing.xcconfig
    .github/workflows/release.yml
    tools/sign_app.sh    tools/make_dmg.sh

That is the set of files the disk image is built from, including the pipeline
that signs and packages it — a change to signing is a change the person
downloading meets. Everything else is not the app: `site/`, `store/`, `docs/`,
the test targets, the store-lane and screenshot tooling, `Makefile`, `iOS/`.

A trailing `[skip ci]` (or any of GitHub's other four spellings) is trimmed
from a listed subject; it is an instruction to CI, not part of the change.
Subjects are otherwise printed as written — they are Markdown on GitHub, and
whatever the author put in them is what they meant.

## Mechanics

### `tools/release_notes.py`

A Python tool with two subcommands, reading nothing but git:

- `changed` prints `true` when at least one commit since the previous release
  touched the app, `false` otherwise. With no previous release it prints
  `true`.
- `notes [--tag vX] [--repository owner/name]` prints the top of the release
  body: the list (or the rebuild sentence), a blank line, and the `Built from`
  line. The compare link is added when both `--tag` and `--repository` are
  given; without them (a local preview) the line ends at the date.

The previous release is `git describe --tags --abbrev=0 --match 'v[0-9]*'
HEAD` — the nearest version tag HEAD descends from. When HEAD is itself tagged
(a rebuild of a released commit) that is the tag, the range is empty, and the
notes say so.

The date is today in UTC, matching the README's download line and the decision
of 2026-09-14. The commit is `git rev-parse --short=7 HEAD`.

**A shallow checkout is refused.** `actions/checkout` fetches one commit by
default; in that checkout `git describe` finds no tag, and the tool would
answer "no previous release" — listing nothing and building everything —
without anyone noticing. Both subcommands check `git rev-parse
--is-shallow-repository` first and exit 2 with a message naming
`fetch-depth: 0`.

Everything else goes to stdout only; diagnostics to stderr. Written for the
system Python on a GitHub runner (no syntax newer than 3.9).

### `.github/workflows/release.yml`

- A new job `changes` on `ubuntu-latest`: checkout with `fetch-depth: 0`, run
  `tools/release_notes.py changed`, expose the answer as the job output `app`.
  The assignment and the echo are two statements so that a tool that fails
  fails the step rather than writing an empty answer.
- `release` gains `needs: [test, changes]` and
  `if: needs.changes.outputs.app == 'true' || github.event_name == 'workflow_dispatch'`.
  (GitHub implies `success()` in front of an `if` that names no status
  function, so a failed test job still blocks the build.) Its checkout gains
  `fetch-depth: 0`.
- The `Release notes` step writes the tool's output to `notes.md` first, then
  appends the install paragraph, the ad-hoc paragraph when unsigned, and the
  checksums, as today. The step's own `Built from` line is removed — the tool
  prints it.
- `test` is unchanged and still runs for every push: its suites check
  `site/strings` and `store/metadata` too.
- `paths-ignore` stays: a documentation-only push still runs nothing.
- The header comment is rewritten to say what the workflow does now.

### Tests

`Packages/Core/Tests/StatusUITests/EveryReleaseListsItsChangesTests.swift`, a
suite in the style of `SiteCataloguesAgree` (which runs a Python tool through
`Process`). It builds a throw-away git repository under the temporary
directory — with `GIT_CONFIG_GLOBAL` and `GIT_CONFIG_NOSYSTEM` set so nothing
on the machine leaks in — makes commits that touch chosen paths, tags one, and
runs the tool in it.

- The commits that touched the app since the tag are listed, oldest first,
  with `[skip ci]` trimmed; a merge commit is not listed, the commit it merged
  is.
- A commit that touched only `site/`, `store/`, `docs/` or
  `Packages/Core/Tests/` is not listed, and with only such commits the notes
  say nothing in the app changed since the tag's version.
- `changed` prints `true` and `false` for those two states, and `true` when
  there is no tag.
- The `Built from` line names HEAD's short hash and carries the compare link
  when `--tag` and `--repository` are given, and no link when they are not.
- A `--depth 1` clone of the fixture is refused with exit 2 and a message
  naming `fetch-depth: 0`.
- Text guards on `release.yml`: the `changes` job runs the tool's `changed`
  subcommand; the `release` job's `if` names that output and
  `workflow_dispatch`; both checkouts that need the history say
  `fetch-depth: 0`; the notes step runs the `notes` subcommand before it
  writes the install paragraph.

### Documents

- `docs/DECISIONS.md` gets an entry: decision, why, cost.
- README: the sentence describing the workflow says it builds on pushes that
  change the app and that the release notes list the commits that did.

## Not in this change

- **Past releases.** The ask was for future versions. The same tool could
  backfill the thirty-six existing bodies through `gh release edit`, given an
  option to read a tag instead of HEAD; that is a separate, optional pass.
- **The site's what's-new page.** It is a curated list of the releases that
  changed something, written by hand in ten languages. Nothing in its text
  becomes false: past rebuilds are still on the releases page, and a rebuild
  asked for by hand still will be.
- **The App Store's `whats_new.txt`.** A different register, written for the
  store's reader in ten languages, cumulative per store version.
- **Trigger paths.** `paths-ignore` is untouched; the gate is the tool, so the
  list of what counts lives in one place rather than in a YAML glob list and a
  Python list that would have to agree.

## Costs, stated

- A change to the store lane's own tooling (`tools/asc_preflight.py`,
  `tools/ExportOptions.AppStore.plist`) no longer runs the TestFlight upload
  until the next change to the app. A hand-started run does.
- Two full-history checkouts per run instead of one shallow one; the
  repository is small.
- The subject of a commit that mixed an app change with tooling is listed as
  written, tooling flavour and all. That is the price of reading the list out
  rather than writing it twice.
