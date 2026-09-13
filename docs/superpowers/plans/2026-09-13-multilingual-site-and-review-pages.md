# Multilingual Site and Review Pages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship softcap.app in ten languages with privacy/support/terms pages,
a search-facing set (faq, changelog, two limits explainers), a marketing-grade
chart, and a real download button — in one deploy.

**Architecture:** `site/` becomes a tiny deterministic build: four body
templates + a shared shell, ten JSON string catalogues, and `build.py` which
renders eighty committed pages plus a multilingual `sitemap.xml` and
`manifest.txt`. The deploy
script ships and verifies whatever the manifest lists. Guard tests extend to
the catalogues and the built output.

**Tech Stack:** hand-written HTML/CSS (no JavaScript, CSP `default-src 'none'`),
python3 stdlib, Swift Testing for guards, Caddy + kamal-proxy for serving.

**Spec:** `docs/superpowers/specs/2026-09-13-multilingual-site-and-review-pages-design.md`

## Global Constraints

- Languages, exactly the app's ten: `en ru es fr ar bn hi id pt-BR zh-Hans`.
- Pages, eight per language: `index privacy support terms faq changelog
  limits/claude limits/codex`. English at the root, other languages under
  lowercase dirs `/ru/ … /pt-br/ … /zh-hans/…`; slugs stay English everywhere.
- No JavaScript on any page; the CSP header in the Caddyfile does not change.
- Brand names `Claude`, `Codex`, `Softcap`, `Anthropic`, `OpenAI` are never
  translated. The window mock stays `dir="ltr"` in every language.
- All generated output is committed; `build.py --check` must pass before
  every commit (wired into the pre-commit hook).
- The support contact is the address the author designated for it. It is not
  written out here: this plan is a published file too, and a value spelled a
  second way walks past an exception written for the first. It enters the
  repository once, in Task 9, together with the exception both guard layers
  need for it.
- Every commit runs the full Swift suite via the pre-commit hook; a task is
  done only when that hook passes without `--no-verify`.
- Commit messages follow the log's style: one imperative sentence, no
  prefixes, no trailers.
- Deviation from the spec's rollout order, on purpose: the chart is
  redesigned *before* templatization (spec said after), so the visual
  iteration happens on one file and the extraction copies final content.

## File Structure

```
site/
  src/shell.html            shared frame: doctype…</head>, header+picker, footer
  src/index.body.html       landing body, {{key}} placeholders
  src/privacy.body.html     legal bodies, same placeholder syntax
  src/support.body.html
  src/terms.body.html
  src/faq.body.html         search-facing bodies; a slash in the page path
  src/changelog.body.html   becomes a dot in the template name
  src/limits.claude.body.html
  src/limits.codex.body.html
  strings/en.json …         ten catalogues, identical key sets
  build.py                  renderer + --check mode
  manifest.txt              generated: every served path
  index.html, privacy/…, ru/…, …   generated pages (committed)
  deploy.sh                 modified: manifest-driven
  Caddyfile                 modified: cache matcher covers all HTML
  check-widths.sh           modified: multi-page, RTL-aware
Packages/Core/Tests/StatusUITests/
  SiteCataloguesAgreeTests.swift      new: parity + freshness + hreflang + RTL + picker
  TheSiteAgreesAboutItselfTests.swift modified: per-page canonicals, all sitemap locs
  LandingMatchesAppTests.swift        availability suite: no change (goes green in Task 1)
docs/DECISIONS.md           four new entries
tools/…pre-commit source…   modified: run build.py --check
```

---

### Task 1: Flip availability on the live page

**Files:**
- Modify: `site/index.html` (lines 364, 410, 661 and the hero block near 410)

**Interfaces:**
- Produces: a hero download link with `class="download"` pointing at
  `https://github.com/milushov/softcap/releases/latest/download/Softcap.dmg`
  (the README's URL); later tasks extract it into templates verbatim.

- [ ] **Step 1: Confirm the guard is red for the expected reason**

Run: `swift test --package-path Packages/Core --filter TheReadmeAndThePageAgreeOnAvailability 2>&1 | tail -5`
Expected: FAIL in `onlyOneOfThemCanBeRight` — page says "in development",
README offers a download.

- [ ] **Step 2: Rewrite the three availability mentions**

In `site/index.html`:
- JSON-LD `description` (line 364): drop the leading `In development. `.
- Hero note (line 410): replace
  `macOS · menu bar, widget, and an iPhone app · <b>in development</b>`
  with `macOS 14+ · menu bar, widgets, and an iPhone app`, and add beneath it
  a download link styled as the page's one button:
  `<p class="cta"><a class="download" href="https://github.com/milushov/softcap/releases/latest/download/Softcap.dmg">Download for macOS</a></p>`
  plus a `.download` CSS rule in the stylesheet (filled pill in `--accent`,
  hover raises, focus visible; matches existing button-ish styles).
- Footer (line 661): replace the in-development sentence with
  `<p>Softcap 0.1.2 is out — <a href="https://github.com/milushov/softcap/releases">release notes</a>.</p>`
- If the JSON-LD has no `"softwareVersion"`, leave it absent (YAGNI).

- [ ] **Step 3: Run the availability and preview suites**

Run: `swift test --package-path Packages/Core --filter 'TheReadmeAndThePageAgreeOnAvailability|PreviewMatchesThePage|ThePageHasAShape' 2>&1 | tail -5`
Expected: PASS. If `PreviewMatchesThePage` quotes the old hero note, update
`site/og-template.html` to the new wording and regenerate `og.png` via the
deploy script's Chrome one-liner.

- [ ] **Step 4: Width check**

Run: `site/check-widths.sh`
Expected: `all clear` twice (default and 24px minimum).

- [ ] **Step 5: Commit (hook must pass without --no-verify)**

```bash
git add site/ && git commit -m "Say the app shipped, because it did"
```

### Task 2: Redesign the chart

**Files:**
- Modify: `site/index.html` (chart section, lines ~523-571; stylesheet)
- Modify: `site/deploy.sh` (staleness grep, lines ~428-434)

**Interfaces:**
- Produces: date labels marked `class="when"`; stat chips markup
  `<ul class="stats"><li><b>3</b> accounts</li>…`; per-account groups
  `<g class="acct a1|a2|a3">` each containing `path.fill`, `path.glow`,
  `path.line`. Later extraction keys the visible strings.

- [ ] **Step 1: Regenerate the data, same story, fresh window**

Recompute the three accounts' polylines for 16 Aug – 13 Sep (weekly resets on
different weekdays, one account with a measured gap re-appearing 4 Sep).
Write a throwaway generator in the scratchpad (not the repo) that emits
monotone-cubic `path d=` strings from weekly (day, percent) readings, y-range
16→172 like today, x-range 60→660, five `class="when"` date labels ending
`13 Sep`. Resets are vertical drops rendered as separate 1px `path.reset`
segments with a gradient stroke fading to transparent.

- [ ] **Step 2: Rebuild the SVG**

Structure (all inside the existing `.chart` container, viewBox `0 0 720 240`):
```html
<ul class="stats">
  <li><b>3</b> accounts</li>
  <li><b>6</b> resets in 30 days</li>
  <li><b>0</b> quota spent measuring</li>
</ul>
<svg viewBox="0 0 720 240" role="img" aria-label="A month of weekly limits for three accounts: smooth curves climbing between resets, with notification thresholds at 80 and 95 percent.">
  <defs>
    <linearGradient id="fill1" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" class="s1"/><stop offset="1" class="s0"/>
    </linearGradient>
    … fill2/fill3 likewise …
  </defs>
  <g class="grid">…5 lines as today…</g>
  <g class="axis y">…100/75/50/25/0% as today…</g>
  <g class="limits">
    <line x1="42" x2="704" y1="47.2" y2="47.2"/>   <!-- 80% -->
    <line x1="42" x2="704" y1="23.8" y2="23.8"/>   <!-- 95% -->
    <text x="704" y="43">80% — first nudge</text>
    <text x="704" y="19">95% — last warning</text>
  </g>
  <g class="acct a1"><path class="fill" d="…Z"/><path class="glow" d="…"/><path class="line" d="…"/></g>
  … a2, a3 (a3 in two runs with the gap) …
  <g class="axis x">…5 <text class="when"> labels…</g>
</svg>
```
CSS: `.stats` chips row (mono numerals, `--fg-2` captions); `.limits line`
dashed `--fg-3` at .5 opacity, labels 9px right-anchored; `.s1`
`stop-color:var(--id-N)` at .28 opacity, `.s0` same colour at 0 (one class
pair per gradient); `.glow` stroke-width 6, opacity .18; `.line`
stroke-width 2.2; draw-in `@keyframes draw {to{stroke-dashoffset:0}}` with
`stroke-dasharray/offset 1200` on `.line` and a fade on `.fill`, both wrapped
in `@media (prefers-reduced-motion: no-preference)`; `.acct:hover .line
{stroke-width:3}` and `.acct:hover .fill{opacity:1.3× via filter:none
approach — use two opacity classes}`. Legend keeps the three names.

- [ ] **Step 3: Rewrite the section copy**

Replace the eyebrow/h2/lede and the caption paragraph: the h2 becomes
`Three subscriptions, one month, zero spent to know it`; the lede sells the
offsets («they renew on different days — the picture says which account is
fresh right now»); the caption keeps the gap-honesty sentence about
`alex` nearly verbatim and adds one about the dashed lines being the
notification thresholds.

- [ ] **Step 4: Update the deploy staleness check**

In `site/deploy.sh` replace the grep
`'<text x="[0-9]*" y="194">[^<]*</text>'` with
`'<text[^>]*class="when"[^>]*>[^<]*</text>'` (same `tail -1 | sed` pipe).

- [ ] **Step 5: Verify visually and mechanically**

Run: `site/check-widths.sh` → all clear twice.
Render screenshots at 1200px light and dark (Chrome headless
`--screenshot`, `--force-dark-mode` off/on… dark via
`--blink-settings=preferredColorScheme=2` is unreliable — instead screenshot
default and with `emulateMedia` unavailable headless: acceptable to
screenshot light only and inspect dark by grepping that every new colour
uses `light-dark()` or a `--id-*`/`--fg-*` variable).
Run: `swift test --package-path Packages/Core 2>&1 | tail -3` → 614+ pass.

- [ ] **Step 6: Commit**

```bash
git add site/ && git commit -m "Let the chart sell what it still tells truly"
```

### Task 3: Extract the build skeleton (en only, byte-for-byte)

**Files:**
- Create: `site/build.py`, `site/src/shell.html`, `site/src/index.body.html`,
  `site/strings/en.json`
- Test: extend none yet — fidelity is checked by `diff`

**Interfaces:**
- Produces: `python3 site/build.py` (renders every page for every catalogue
  present), `python3 site/build.py --check` (exit 1 on drift, listing files),
  placeholder syntax `{{key}}`, shell tokens `{{lang}}`, `{{dir}}`,
  `{{og_locale}}`, `{{root}}` (prefix to reach `/`: empty for en, `../` for
  others), `{{alternates}}`, `{{picker}}`, `{{body}}`, `{{canonical}}`.
- Produces: `site/manifest.txt` — relative served paths, sorted, one per
  line, assets included.

- [ ] **Step 1: Split `index.html` into shell + body with zero text changes**

`shell.html` holds everything through `</head>` plus header/nav and the
footer; `index.body.html` holds `<main>…</main>`. Every human-readable
string in both moves to `strings/en.json` as `{{section.slug}}` keys
(title, meta description, og/twitter strings, JSON-LD name/description,
aria-labels, image alt, every visible sentence, the chart's stat chips,
threshold labels, date labels stay literal in the body — dates are data,
not copy). Attribute strings use the same `{{…}}` syntax. Nothing else
changes in this step: no picker yet, no hreflang.

- [ ] **Step 2: Write `build.py`**

Behaviour (python3, stdlib, ~150 lines):
- `LANGS = ["en","ru","es","fr","ar","bn","hi","id","pt-BR","zh-Hans"]`,
  `DIRS = {lang: "" if lang=="en" else lang.lower()+"/"}`,
  `RTL = {"ar"}`, `OG = {"en":"en_US","ru":"ru_RU","es":"es_ES","fr":"fr_FR",
  "ar":"ar_SA","bn":"bn_BD","hi":"hi_IN","id":"id_ID","pt-BR":"pt_BR",
  "zh-Hans":"zh_CN"}`, `PAGES = ["index","privacy","support","terms","faq",
  "changelog","limits/claude","limits/codex"]` (template name = page path
  with `/`→`.`; pages render only when their body template exists, so this
  task ships with only `index`).
- Load catalogues that exist; refuse (exit 2, message) if key sets or the
  set of `{…}`-style placeholders inside values differ between catalogues.
- Substitution is `str.replace` over sorted keys; `{{json:key}}` substitutes
  the JSON-escaped value (`json.dumps(v)[1:-1]`) for use inside JSON-LD; an
  unresolved `{{` in output is a hard error naming file and offset.
- Renders only languages whose catalogue file exists (so this task, with
  only `en.json`, reproduces today's site exactly).
- Writes pages `dist-path = DIRS[lang] + ("" if page=="index" else page+"/") + "index.html"`.
- Generates `sitemap.xml` in the multilingual form — one `<url>` per
  rendered page, each carrying `xhtml:link rel="alternate"` entries for all
  ten languages plus `x-default` — and `manifest.txt` (rendered pages + the
  five assets `icon.svg og.png favicon.ico robots.txt sitemap.xml`).
  While only en renders, the sitemap keeps today's shape (no alternates for
  languages that do not exist yet), so fidelity still holds.
- `--check`: render into `tempfile.mkdtemp()`, compare byte-wise against
  the working tree, print differing paths, exit 1 on any.

- [ ] **Step 3: Prove fidelity**

Run: `python3 site/build.py && git diff --stat site/index.html`
Expected: no diff at all. `git status` shows only the new src/strings/build
files plus `manifest.txt` and a `sitemap.xml` that must equal the old one —
if sitemap differs, adjust the generator until it matches today's file.

- [ ] **Step 4: Commit**

```bash
git add site/ && git commit -m "Teach the site to be built without changing a byte"
```

### Task 4: Picker, hreflang, per-page canonicals (still en-only content)

**Files:**
- Modify: `site/src/shell.html`, `site/build.py`, `site/strings/en.json`,
  stylesheet inside shell
- Modify: `Packages/Core/Tests/StatusUITests/TheSiteAgreesAboutItselfTests.swift`

**Interfaces:**
- Produces: `{{alternates}}` expands to ten `<link rel="alternate"
  hreflang…>` + `x-default`; `{{picker}}` expands to the `<details>` picker;
  every page's `<link rel="canonical">` is its own URL.
- Native names table in `build.py`:
  `NATIVE = {"en":"English","ru":"Русский","es":"Español","fr":"Français",
  "ar":"العربية","bn":"বাংলা","hi":"हिन्दी","id":"Bahasa Indonesia",
  "pt-BR":"Português (Brasil)","zh-Hans":"中文（简体）"}` and
  `ENGLISH = {…"ar":"Arabic"… full ten…}`.

- [ ] **Step 1: Shell gains the picker and the cluster**

Header right side and footer both render `{{picker}}`:
```html
<div class="lang" aria-label="{{shell.language}}">
  <span class="lang-code" aria-current="true">EN</span>
  <details class="lang-more">
    <summary><bdi dir="ltr">+9</bdi></summary>
    <div class="lang-panel">
      <a class="lang-row" lang="ru" href="{{root}}ru/{{page_path}}">
        <span class="code">RU</span><span class="names"><span>Русский</span><span>Russian</span></span></a>
      …ten rows, current row is a <span aria-current="true"> with a tick…
    </div>
  </details>
</div>
```
`{{page_path}}` is `""|"privacy/"|"support/"|"terms/"`. Panel CSS: absolute
under the summary in the header variant, opening upward in the footer
variant; `summary::-webkit-details-marker{display:none}`; rows are the
page's existing link styling; the whole thing is ~40 lines of CSS using
existing variables only. `shell.language` = "Language" in `en.json`.

- [ ] **Step 2: build.py assembles alternates + canonical + og:locale per page**

`<link rel="alternate" hreflang="{lang}" href="https://softcap.app/{dirs}{page_path}">`
for all ten + `hreflang="x-default"` → English URL. `og:url`, `canonical`
and JSON-LD `"url"` become the page's own URL (JSON-LD only exists on the
landing).

- [ ] **Step 3: Adapt `TheSiteAgreesAboutItself`**

`everyAddressSharesTheCanonicalOrigin` now asserts every `<loc>` in
`sitemap.xml` and every `hreflang` href shares the canonical **origin**
(not equality with the root URL), and that the alternates listed on
`site/index.html` all exist as files. Keep the deploy-domain assertion.

- [ ] **Step 4: Rebuild, test, commit**

Run: `python3 site/build.py && swift test --package-path Packages/Core 2>&1 | tail -3`
`site/check-widths.sh` (the header grew a control; 320px must still hold).
```bash
git add site/ Packages/ && git commit -m "Give every page its address and a way to switch language"
```

### Task 5: The three legal bodies in English

**Files:**
- Create: `site/src/privacy.body.html`, `site/src/support.body.html`,
  `site/src/terms.body.html`
- Modify: `site/strings/en.json`, `site/build.py` (PAGES already lists them —
  they start rendering), `site/src/shell.html` (nav link to `/support/`)

**Interfaces:**
- Consumes: shell tokens from Task 3/4.
- Produces: key namespaces `privacy.*`, `support.*`, `terms.*`; the legal
  layout class `.legal` (one column, `max-width` matching `.wrap`, `<dl>`
  reuse for FAQ).

- [ ] **Step 1: Check the license before writing terms**

Run: `head -3 LICENSE`
The terms' license section must defer to that file by its real name (MIT,
etc.), not restate it.

- [ ] **Step 2: Write the three bodies + en strings**

Content per the spec's "The pages" section, structured as `<section><h2>`
blocks mirroring the landing's type scale. Support's contact paragraph is
written with the `{{support.contact_email}}` token; a mailbox-shaped
stand-in would trip the personal-data guard and lie besides, so `en.json`
carries the sentinel `"§EMAIL§"` until Task 9 — `build.py` fails on
unresolved `{{`, not on sentinel text, and Task 9 replaces the sentinel in
all ten catalogues in the same commit that allowlists the real address. The GitHub issues
link `https://github.com/milushov/softcap/issues` appears beside it from the
start.

- [ ] **Step 3: Build, eyeball, test, commit**

Run: `python3 site/build.py && open site/privacy/index.html` (visual pass),
`site/check-widths.sh`, full swift suite.
```bash
git add site/ && git commit -m "Write the pages a review asks for, in English first"
```

### Task 5b: The search-facing pages in English

**Files:**
- Create: `site/src/faq.body.html`, `site/src/changelog.body.html`,
  `site/src/limits.claude.body.html`, `site/src/limits.codex.body.html`
- Modify: `site/strings/en.json`, `site/src/shell.html` (footer nav),
  `site/src/index.body.html` (two in-copy links to the explainers),
  `site/src/support.body.html` (product questions move to faq; link both ways)

**Interfaces:**
- Consumes: `{{json:key}}` from Task 3; `{{root}}`/`{{page_path}}` tokens.
- Produces: footer nav `<nav class="site-map">` naming all eight pages
  (localized labels under `shell.nav.*`); breadcrumb block
  `<nav class="crumbs">` + `BreadcrumbList` JSON-LD at the top of every
  non-root body (home → page), keys `shell.crumbs.home` etc.

- [ ] **Step 1: Gather the real facts before writing**

Run: `gh release list -R milushov/softcap` and `gh release view <tag>` for
each — the changelog page paraphrases actual release notes, one dated
section per release, newest first. For the explainers, source claims from
the landing's own guarded copy and the app's documented behaviour
(five-hour session + weekly caps, offset resets, headers-of-a-successful-
request for Codex, `~/.codex/sessions` for local reads, live endpoint for
Claude). No claim the app does not embody.

- [ ] **Step 2: Write the four bodies + en keys**

faq: 10–12 `<section>` Q&A pairs; a `<script type="application/ld+json">`
FAQPage built from the same keys via `{{json:faq.qN}}`/`{{json:faq.aN}}`.
changelog: `<article>` per release, `<time datetime>` dates, h2 = version.
limits/*: ~500 words each — how the limit behaves, when it resets, what
counts against it, then one closing section on reading it from the menu
bar. Breadcrumbs + BreadcrumbList on all four (and on the three legal
pages from Task 5, added here).

- [ ] **Step 3: Build, run the suites, width-check, commit**

Run: `python3 site/build.py && swift test --package-path Packages/Core 2>&1 | tail -3 && site/check-widths.sh`
```bash
git add site/ && git commit -m "Answer the searches a limit-hit person makes"
```

### Task 6: Nine catalogues

**Files:**
- Create: `site/strings/{ru,es,fr,ar,bn,hi,id,pt-BR,zh-Hans}.json`

**Interfaces:**
- Consumes: `en.json` as the source of truth; the app's
  `Packages/Core/Sources/StatusUI/Resources/<lang>.lproj/Localizable.strings`
  as the terminology reference (session/weekly limit, quiet hours, snapshot
  age — reuse the app's established wording per language).

- [ ] **Step 1: Translate in three parallel batches (subagents)**

Batch A: ru, es, fr. Batch B: ar, hi, bn. Batch C: id, pt-BR, zh-Hans.
Each agent receives: `en.json`, the language's app catalogue, the brand
no-translate list, the instruction that `§EMAIL§` and `{{…}}`-shaped and
date-like values stay verbatim, and returns the full JSON file.

- [ ] **Step 2: Build with all ten and inspect the fragile three**

Run: `python3 site/build.py` — parity check inside build.py is the gate.
Read `ar/index.html` (RTL punctuation), `bn/index.html`, `hi/index.html`
headline blocks by eye.

- [ ] **Step 3: Commit**

```bash
git add site/strings site/*.html site/*/ site/manifest.txt site/sitemap.xml
git commit -m "Speak all ten languages on the site, not just in the app"
```

### Task 7: RTL pass + guard tests for the new machinery

**Files:**
- Modify: `site/src/shell.html` stylesheet (logical properties), `build.py`
  (`dir="rtl"` already emitted — verify), window-mock wrapper `dir="ltr"`
- Create: `Packages/Core/Tests/StatusUITests/SiteCataloguesAgreeTests.swift`

**Interfaces:**
- Produces: suite `SiteCataloguesAgree` with tests
  `everyCatalogueHasTheSameKeys`, `theBuiltPagesAreFresh` (runs
  `python3 site/build.py --check` via `Process`, skipped with a recorded
  message when python3 is absent), `everyPageListsAllTenAlternates`,
  `theArabicPagesReadRightToLeft`, `thePickerNamesAllTenOnEveryPage`.

- [ ] **Step 1: Sweep the stylesheet for physical properties**

`grep -n 'left\|right\|text-align' site/src/shell.html` — convert to
`inline-start/inline-end` equivalents where mirroring is wanted; keep the
window mock and the chart LTR by wrapping mock in `<div dir="ltr">` (chart
axis numbers already isolate fine; verify visually on `ar/index.html`).

- [ ] **Step 2: Write the five tests (real code, ~120 lines)**

Parity: decode every `site/strings/*.json` as `[String:String]`, compare
key sets against en's, and compare the multiset of `{{…}}` tokens per key.
Freshness: run build.py --check, assert exit 0, surface stdout on failure.
Alternates/picker/RTL: string-scan the built pages (same style the existing
suites use — regex over the file, no DOM parser).

- [ ] **Step 3: Run, fix, commit**

Full suite + `site/check-widths.sh`.
```bash
git add site/ Packages/ && git commit -m "Guard the catalogues the way the app guards its own"
```

### Task 8: Caddyfile, deploy.sh, check-widths, pre-commit

**Files:**
- Modify: `site/Caddyfile` (cache matcher), `site/deploy.sh` (manifest),
  `site/check-widths.sh` (multi-page), the pre-commit hook source that
  `tools/install-hooks.sh` installs (locate via `grep -rl 'suite does not
  pass' tools/`), adding `python3 site/build.py --check`.

**Interfaces:**
- Consumes: `site/manifest.txt` from Task 3.

- [ ] **Step 1: Caddyfile**

Replace the `@page` matcher with
`@page path / */ /index.html */index.html` (the four shapes every HTML URL
takes) — assets keep their week-long rules. `handle_errors` unchanged.

- [ ] **Step 2: deploy.sh reads the manifest**

- `SERVED=()` → `mapfile -t SERVED < "$HERE/manifest.txt"`; floor check
  becomes `-lt 85` with the message updated.
- Shipping: assemble `"$WORK/stage"` via
  `rsync -a --delete --files-from="$HERE/manifest.txt" "$HERE/" "$WORK/stage/"`
  then `rsync -az -e "ssh $SSH_OPTS" --delete "$WORK/stage/" "$HOST:$REMOTE/dist/"`.
- Verification loop: URL for `X/index.html` is `https://$DOMAIN/X/`; for
  `index.html` it is `/`; assets unchanged. Header loop: `no-cache` asserted
  for `/`, `/privacy/`, `/faq/`, `/ru/`, `/ru/support/`, `/ru/limits/claude/`
  (samples spanning both matcher shapes and both nesting depths), assets as
  today.
- `snapshot_current`/`roll_back` floors change from `${#SERVED[@]}` file
  count in a flat dir to `find dist -type f | wc -l` compared against the
  manifest length (the tree is nested now).

- [ ] **Step 3: check-widths takes pages as arguments**

`PAGES=${PAGES:-index.html faq/index.html limits/claude/index.html ru/index.html ar/index.html bn/index.html}`;
the harness loop copies each page (and rewrites nothing — relative asset
links resolve identically from the temp dir), renders the same width list
per page, prefixes verdict lines with the page. Runtime stays under a
minute: 4 pages × 2 font floors.

- [ ] **Step 4: pre-commit runs the freshness check**

Add `python3 site/build.py --check` before the Swift suite in the hook
source; reinstall via `tools/install-hooks.sh`.

- [ ] **Step 5: Commit**

```bash
git add site/ tools/ && git commit -m "Ship and verify the whole tree, not six files"
```

### Task 9: The published address and the decision log

**Files:**
- Modify: the `NoPersonalDataInTheRepository` guard (locate:
  `grep -rl 'example' Packages/Core/Tests | xargs grep -l mail`), ten
  `site/strings/*.json` (sentinel → real address), `docs/DECISIONS.md`
- Modify: `~/.claude/softcap-hooks/private-allowed.txt` (outside the repo)

- [ ] **Step 1: Allow exactly one address in both guard layers**

Public guard: the mail-shape rule gains an allowlist containing the one
literal address, with a comment saying it is the App Store support contact,
published on purpose. Private layer: append the same literal to
`private-allowed.txt`.

- [ ] **Step 2: Replace the sentinel in all ten catalogues, rebuild**

`§EMAIL§` → the real address (a `mailto:` link in the body templates).
Run `python3 site/build.py`.

- [ ] **Step 3: Four DECISIONS.md entries**

(1) availability flip, superseding 31 Aug's honest-unavailability entry and
pointing at it; (2) the site is generated into ten committed languages —
what/why/cost (cost: 40 files churn per copy edit, mitigated by --check);
(3) the support address is published deliberately — why the guard gained
its one exception; (4) the chart trades the didactic sawtooth for a
marketing drawing that still refuses to invent readings.

- [ ] **Step 4: Commit (hook now proves the exception works)**

```bash
git add site/ Packages/ docs/ && git commit -m "Publish the support address on purpose and say so"
```

### Task 10: Full verification, screenshots, the one deploy

- [ ] **Step 1: The whole gauntlet locally**

`python3 site/build.py --check` → clean. `site/check-widths.sh` → all
clear ×8 combos. `swift test --package-path Packages/Core` → all pass.
`git status` → clean tree.

- [ ] **Step 2: Screenshots for the author**

Headless Chrome, 1200×2400: `/`, `/ru/`, `/ar/`, `/privacy/` — save to the
scratchpad, attach to the final report.

- [ ] **Step 3: Deploy and verify live**

`site/deploy.sh` (its own digest loop covers all ~45 files), then
`site/deploy.sh --status` → "serving exactly what is in this checkout".
Spot-check live: `curl -s https://softcap.app/ru/ | grep -c 'hreflang'` →
11, `curl -sI https://softcap.app/ar/ | grep Cache-Control` → no-cache,
`curl -s https://softcap.app/faq/ | grep -c 'FAQPage'` → 1, and the
sitemap answers with `xhtml:link` entries.

- [ ] **Step 4: Push**

```bash
git push
```
(pre-push scan runs the private layer over everything).

## Self-Review Notes

- Spec coverage: availability→T1, chart→T2, build→T3/4, legal pages→T5,
  SEO pages+breadcrumbs+footer nav→T5b, translations→T6, RTL+tests→T7,
  infra→T8, address+decisions→T9, rollout→T10. Multilingual sitemap and
  manifest live in T3; og:locale in T4; FAQPage JSON-LD in T5b. Covered.
- The `§EMAIL§` sentinel keeps Task 5 honest without smuggling the address
  past Task 9's guards; build.py only hard-fails on unresolved `{{`.
- Type consistency: `build.py --check` exit codes (0/1 drift/2 parity),
  manifest name, `class="when"`, `.acct/.line/.fill/.glow`, `{{page_path}}`
  are each defined once and reused by name.
