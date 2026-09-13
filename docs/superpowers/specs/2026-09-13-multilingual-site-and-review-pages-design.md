# The site in ten languages, the review pages, and a glossier chart

Date: 2026-09-13. Status: approved for implementation.

## Context

The landing at softcap.app is one hand-written English HTML file behind Caddy,
deliberately free of JavaScript (`Content-Security-Policy: default-src 'none'`)
and guarded by test suites that keep its claims true to the code. Three things
now outgrow it:

1. **App Store review needs pages.** A submission requires a Support URL and a
   Privacy Policy URL; a Terms of Use page completes the set. None exist.
2. **The app ships in ten languages; the site speaks one.** The reader who gets
   a localized app from an English-only page is a mismatch the project already
   solved once, in the app, with per-language catalogues and parity tests.
3. **The page still says "in development" while the README offers a download.**
   Release v0.1.2 is live and the README links to it, so
   `TheReadmeAndThePageAgreeOnAvailability` is red: the page must flip to
   "shipped". The chart, the page's one picture of usage over time, also ends
   two weeks ago and was drawn for legibility rather than appeal; it is being
   redesigned for marketing at the same time.

Decisions taken with the author before writing this spec: the chart goes
glossy (curves, fills, big numbers) rather than staying didactic; the page set
is complete (privacy, support, terms — not just the required two); everything
lands in one deploy rather than incrementally.

## Goals

- Every page in the ten app languages: `en`, `ru`, `es`, `fr`, `ar`, `bn`,
  `hi`, `id`, `pt-BR`, `zh-Hans`.
- Eight pages per language: the landing, `privacy`, `support`, `terms`,
  plus the search-facing set — `faq`, `changelog`, and two explainers,
  `limits/claude` and `limits/codex`, on the questions people actually
  search for (what the five-hour and weekly limits are, when they reset,
  how to see what is left without spending it).
- A language picker on every page that works with JavaScript disabled.
- A chart that sells the product without claiming a reading nobody took.
- A download button, because the download now exists.
- The existing guard philosophy extended, not weakened: generated pages are
  committed, drift is caught by tests, and the deploy verifies what it shipped.

## Non-goals

- No JavaScript anywhere. The CSP stays `default-src 'none'`.
- No per-language preview images: `og.png` stays English for all locales.
- No comparison ("vs") pages, no blog, no doorway pages. Every SEO page
  states facts the guard suites could check; a page that exists only to
  rank is the kind of page this site refuses to be.
- No localized URL slugs: paths stay English everywhere (`/ru/limits/claude/`),
  and `hreflang` carries the language signal.
- No translation of brand names (`Claude`, `Codex` — same rule as the app) and
  no localization of the window mock, which depicts an English macOS UI.
- No server-side language negotiation. Caddy serves files; the picker is links.

## Architecture

`site/` becomes a small build, with its output committed:

```
site/
  src/
    shell.html          the shared frame: head, picker, footer
    index.body.html     per-page bodies with {{key}} placeholders
    faq.body.html … changelog, limits/claude, limits/codex likewise
    privacy.body.html
    support.body.html
    terms.body.html
  strings/
    en.json … zh-Hans.json   ten catalogues, identical key sets
  build.py              renders 80 pages + sitemap.xml + manifest.txt
  manifest.txt          every served path, one per line (generated)
  index.html            generated: English landing at its historic path
  privacy/index.html    generated …and so on for every page and language
  ru/index.html
  ru/privacy/index.html …
```

- **`build.py`** is python3, standard library only, deterministic output.
  It refuses to run when any catalogue is missing a key another one has, or
  when placeholders disagree — the same floor the app's catalogues stand on.
  `build.py --check` rebuilds into a temporary directory and fails when the
  committed output differs, so a template edit cannot be committed without its
  regenerated pages.
- **Output is committed.** The repository stays an exact record of what is
  live, the existing suites keep reading `site/index.html` at its old path,
  and the deploy needs no build step on the way out.
- **URLs**: English at the root (`/`, `/privacy/`, `/support/`, `/terms/`),
  other languages under lowercase directories (`/ru/`, `/pt-br/`,
  `/zh-hans/`, …). Every page carries the full `hreflang` cluster plus
  `x-default` (pointing at English), its own `og:locale`, its own canonical.
  `sitemap.xml` lists all 80 pages.
- **RTL**: the Arabic pages set `dir="rtl"` on `<html>`. The stylesheet moves
  to logical properties where a physical one would mirror wrongly; the window
  mock is wrapped in `dir="ltr"` on purpose. Numbers adjacent to `+` or `%`
  are isolated with `<bdi>` where the bidi algorithm would reorder them.
- **The picker**: the current language's code shown flat, a
  `<details>/<summary>` disclosure listing all ten with native and English
  names, a tick on the current one. Plain links, no script. It appears in the
  header and the footer of every page.

## The pages

Skeletons follow the shape a review expects; every sentence is true of
Softcap specifically:

- **Privacy**: there are no accounts and no analytics; readings and history
  live on the device; credentials live in the keychain. Exactly three kinds
  of network traffic exist, named: usage requests to Anthropic and OpenAI
  made with the reader's own credentials (the app's function), optional
  error reports scrubbed of paths, addresses and anything token-shaped
  before sending, and a daily update check against the release feed — the
  last two each with the setting that turns them off. Nothing is sold or
  shared; the app is not directed at children and collects nothing from
  anyone. A last-updated date and the support contact close the page.
- **Support**: the support mailbox and the repository's issue tracker;
  what to expect in response time; requirements (macOS 14+, iOS 17+);
  a FAQ drawn from real behaviour — keychain prompts and when they appear,
  browser sign-in per provider, local Codex accounts and snapshot age,
  notification thresholds and quiet hours, removing an account and its data,
  turning off error reports and the update check. Links to privacy and terms.
- **Terms**: acceptance, the software license the repository already grants
  (the page defers to `LICENSE` rather than inventing a second license),
  acceptable use, no warranty, limitation of liability, the non-affiliation
  line (Anthropic, OpenAI), changes, contact.
- The support address is published deliberately. The repository guard that
  forbids mail addresses gains a documented exception for exactly that one
  string, recorded in `docs/DECISIONS.md`; nothing else is loosened.

## The search-facing pages and technical SEO

- **`faq`**: ten-plus real questions with real answers (what gets measured,
  what leaves the machine, why a snapshot has an age, what the thresholds
  mean, what happens on rotation), each pair also emitted as `FAQPage`
  JSON-LD so the answer can appear on the results page itself. The support
  page keeps only troubleshooting; product questions move here and the two
  pages link each other.
- **`changelog`**: one entry per published release, drawn from the real
  release notes — versions, dates, and what changed in a sentence or three.
  It exists because a dated page that changes with every release is the
  freshness signal a one-page site never sends.
- **`limits/claude`, `limits/codex`**: plain explanations of how each
  provider's subscription limits behave (five-hour session and weekly caps,
  offset resets, where the numbers come from) and, at the end, how Softcap
  shows them. They target the searches people make when they hit a limit;
  they earn the click by answering before they sell.
- **Structured data**: the landing keeps `SoftwareApplication`; `faq` adds
  `FAQPage`; every page below the root adds `BreadcrumbList`. Localized
  strings enter JSON-LD through a JSON-escaping substitution in the
  builder, never by hand.
- **`sitemap.xml`** upgrades to the multilingual form: every URL entry
  carries `xhtml:link` alternates for all ten languages plus `x-default`.
- **Internal links**: the footer grows a small nav naming every page; the
  landing's feature copy links the two explainers where it mentions limits;
  breadcrumbs make every page reachable in two clicks from any other.

## The chart

Same section, new drawing, at `viewBox` around 720×240:

- **Curves**: monotone-cubic interpolation between the same per-week
  readings — no overshoot, no invented peaks. Weekly resets stay as drops,
  drawn as thin fades rather than hard verticals. The gap in one account's
  line stays a gap; the caption keeps saying why.
- **Fills**: a vertical gradient under each line in that account's identity
  colour, fading to transparent, `stop-color` driven by the existing
  `--id-*` variables so both themes work.
- **Glow**: each line duplicated once underneath at triple width and low
  opacity. No SVG filters.
- **Thresholds**: dashed guides at 80% and 95% labelled as the notification
  levels — the picture now shows the feature.
- **Numbers**: a row of three stat chips above the chart (localized):
  three accounts · resets on different days · zero quota spent measuring.
- **Motion**: lines draw in once via `stroke-dashoffset`, fills fade after,
  everything inside `@media (prefers-reduced-motion: no-preference)`.
  Hovering an account's group brightens its line and fill — CSS only.
- **Dates**: the window ends 13 September 2026. The deploy's staleness check
  moves from the old `y="194"` pattern to a `class="when"` marker on the
  date labels, so the check survives redesigns.
- The section copy is rewritten for the new drawing; the accessibility label
  describes what is actually shown.

## Availability

- The hero gains a download button pointing at the same
  `releases/latest/download` URL the README uses; requirements sit beside it.
- The footer line about the machine it was written on is replaced with a
  shipped-tense line; the JSON-LD description drops "In development.".
- `TheReadmeAndThePageAgreeOnAvailability` returns to green with no test
  change: the code under test changes, not the expectation.
- A `docs/DECISIONS.md` entry marks the 31 August "honest unavailability"
  decision as superseded, pointing back at it.

## Infrastructure

- **Caddyfile**: `Cache-Control: no-cache` extends from the two spellings of
  the root page to every HTML path (`/`, `*/`, `/index.html`,
  `*/index.html`); the three long-cached assets keep their week.
- **deploy.sh**: the hand-written `SERVED` array is replaced by
  `site/manifest.txt`. The floor check requires at least 85 entries
  (80 pages + 5 assets); the copy, the deletion protection, the
  post-deploy digest loop and the header checks all iterate the manifest.
  The snapshot/`--rollback` path already covers the whole `dist/` tree and
  needs only the floor number updated.
- **check-widths.sh**: renders `en`, `ru`, `ar` and `bn` landings (worst
  cases for length, script and direction) at the same widths and font
  floors as today; the four legal pages are prose and are covered by the
  English render plus the RTL render.
- **Hooks/CI**: `build.py --check` runs from the pre-commit hook and from a
  test, so the built pages cannot drift from their sources in either place.

## Tests

- New: catalogue parity (key sets and placeholders across the ten files),
  build freshness (`--check`), hreflang reciprocity (every page lists all
  ten alternates and `x-default`, and the listed files exist), RTL smoke
  (the Arabic landing declares `dir="rtl"`), picker completeness (ten
  entries on every page).
- Updated: `TheSiteAgreesAboutItself` learns that canonicals now differ per
  page but share one origin; the deploy-shape suite follows the manifest
  change; the chart-related copy assertions follow the new section text.
- Unchanged on purpose: the availability suite, the no-strings-in-Core scan,
  and the claim guards — the claims stay true, so the guards stay put.

## Rollout

One release at the end, in this order: the availability flip on the current
page first, because the guard suite is red until it lands and every commit
runs that suite → build skeleton reproducing the fixed page byte-for-byte →
the chart in template form → the three legal pages in English → the nine
translations → Caddyfile, deploy.sh, check-widths, hooks → full test suite,
width checks, `--check`, screenshots to the author → a single deploy,
verified by the script's own digest loop.

## Risks

- **Translation quality**: the nine non-English versions are written
  in-session, like the app's catalogues were; a native pass later is welcome
  and the catalogues make it cheap.
- **RTL regressions**: bounded by the logical-properties pass and the Arabic
  render in check-widths.
- **An 85-file deploy**: the rollback restores the entire previous tree in
  one step, and the deploy refuses to start from an empty manifest.
