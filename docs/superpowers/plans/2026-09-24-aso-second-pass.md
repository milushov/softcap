# ASO Second Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the App Store listing the one token it cannot currently match, give the app its first ratings, and leave behind a measurement series instead of a memory.

**Architecture:** Three independent pieces. Two are tools that measure (a rank log appended by `aso_research.py`, a reader for the analytics report already ordered from App Store Connect). One is a product change in two halves — a pure decision type in `Monitoring` that says whether this is a moment to ask for a rating, and three lines in the App target that call StoreKit when it says yes. The keyword edit is data, held by a test.

**Tech Stack:** Python 3 (standard library only — no third-party modules are installed on the machines that run these tools), Swift 6.2, Swift Testing, StoreKit.

## Global Constraints

- **Documentation is English.** README, decision log, specs, plans, code comments. Conversation with the author is Russian. (`CLAUDE.md`)
- **No human-facing strings in `Packages/Core`.** Core returns identifiers and numbers; labels are assembled by `StatusUI`. Enforced by `CoreHasNoHumanStrings`. Nothing in this plan adds a string — `SKStoreReviewController` supplies its own text, so no catalogue work and no ten-language edit.
- **Core stays portable.** `Monitoring` must not import StoreKit or AppKit. Enforced by `CoreStaysPortable`. The StoreKit call lives in the App target.
- **Nothing private in the repository.** No home directory or absolute path from one machine, no machine name, no account identifier taken from a running instance, nothing credential-shaped, no routable host address. Enforced by `NoPersonalDataInTheRepository` and by the private hook layer `core.hooksPath` already points at. **Do not run `tools/install-hooks.sh`** — it repoints `core.hooksPath` at `tools/hooks` and drops the private layer.
- **App Store Connect credentials come from the environment**, exactly as `push_store_metadata.py` and `asc_preflight.py` already read them: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`. No tool writes them anywhere, and no key path appears in a committed file.
- **App Store Connect paths need the `/v1` prefix.** Without it the API answers `404 NOT_FOUND` with "The path provided does not match a defined resource type", which reads like a missing app rather than a missing prefix.
- **Keyword field limits:** name ≤ 30, subtitle ≤ 30, keywords ≤ 100, description ≤ 4000, promotional_text ≤ 170, whats_new ≤ 4000 — counted in UTF-16, which is how Apple counts. Held by `StoreListingFitsTheStore`.
- **Ten locales, exactly:** `en-US`, `ru`, `es-ES`, `es-MX`, `fr-FR`, `pt-BR`, `hi`, `id`, `ar-SA`, `zh-Hans`.
- **Run the Swift suite with `make test`** (it runs `swift test` inside `Packages/Core`). The App target is built with `make build`.
- **Commit messages carry no session link and no agent trailer.** The message ends on its last line of real content.
- **The working directory is shared with other sessions**, so the git index is shared. Always commit with an explicit pathspec — `git commit -m "…" -- path/one path/two` — never a bare `git commit` that would sweep up another session's staged work.

---

### Task 1: The rank log

A measurement nobody wrote down is not a series. `aso_research.py rank` prints and forgets; this gives it a file to append to, a default set of terms so two runs a fortnight apart are comparable, and a test that polices the file's shape.

**Files:**
- Modify: `tools/aso_research.py` (module docstring; add `DEFAULT_TERMS`, `RANKS`, `rank_row`, `log_rows`; rework `main`'s argument handling and the `rank` branch)
- Create: `store/ranks.tsv`
- Test: `Packages/Core/Tests/StatusUITests/TheRankLogIsASeriesTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `store/ranks.tsv` with the header `date\tstorefront\tterm\trank\tsearched` and one row per measured term. `rank` is a positive integer or empty when the app was not found; `searched` is how many results the storefront returned. Task 2 does not read it; the fortnight measurement in the Sequence section does.

- [ ] **Step 1: Write the failing test**

Create `Packages/Core/Tests/StatusUITests/TheRankLogIsASeriesTests.swift`:

```swift
import Testing
import Foundation
@testable import StatusUI

/// `aso_research.py rank --log` appends to `store/ranks.tsv`, and the point of
/// the file is that two runs a fortnight apart can be subtracted from each
/// other.
///
/// That only works if both runs asked the same questions, so the term list
/// lives in the tool rather than in whoever ran it, and if every row can be
/// parsed the same way. The previous pass ended on "measure again in a
/// fortnight" and could not, because the first measurement was printed to a
/// terminal that has since been closed.
@Suite struct TheRankLogIsASeries {

    private static let header = "date\tstorefront\tterm\trank\tsearched"

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // StatusUITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // Core
            .deletingLastPathComponent()   // Packages
    }

    private static func tool() throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent("tools/aso_research.py"),
                   encoding: .utf8)
    }

    /// The terms are the tool's, not the caller's: a run that measured seven
    /// terms and a run that measured nine do not make a series.
    @Test func theToolCarriesItsOwnTermList() throws {
        let source = try Self.tool()
        guard let start = source.range(of: "DEFAULT_TERMS = ["),
              let end = source.range(of: "]", range: start.upperBound..<source.endIndex) else {
            Issue.record("aso_research.py no longer carries a DEFAULT_TERMS list")
            return
        }
        let terms = source[start.upperBound..<end.lowerBound]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \n\"'")) }
            .filter { !$0.isEmpty }

        #expect(terms.count >= 5, "the list measures \(terms) — too few to say anything")
        #expect(Set(terms).count == terms.count, "a term is measured twice — \(terms.sorted())")
        for baseline in ["claude usage", "ai usage", "codex usage", "claude code"] {
            #expect(terms.contains(baseline), """
                \(baseline) is one of the four terms the 2026-09-20 pass set as \
                the baseline; dropping it from the list ends the series
                """)
        }
    }

    /// The header is written by the tool and read here, so a column added on
    /// one side and not the other is a failed test rather than a file that
    /// quietly stops parsing.
    @Test func theToolWritesTheHeaderThisTestExpects() throws {
        #expect(try Self.tool().contains(Self.header.replacingOccurrences(of: "\t", with: "\\t")), """
            aso_research.py does not write the header \(Self.header.debugDescription)
            """)
    }

    /// Only checked once the file exists — the test has to pass on a clone that
    /// has never run the tool.
    @Test func everyRowThatHasBeenWrittenCanBeRead() throws {
        let path = Self.repositoryRoot.appendingPathComponent("store/ranks.tsv")
        guard let text = try? String(contentsOf: path, encoding: .utf8) else { return }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        #expect(lines.first == Self.header, "store/ranks.tsv starts \(lines.first ?? "empty")")

        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(identifier: "UTC")

        for line in lines.dropFirst() {
            let cells = line.components(separatedBy: "\t")
            #expect(cells.count == 5, "five columns expected, \(cells.count) in \(line.debugDescription)")
            guard cells.count == 5 else { continue }
            #expect(day.date(from: cells[0]) != nil, "\(cells[0].debugDescription) is not a yyyy-MM-dd date")
            #expect(!cells[1].isEmpty, "no storefront in \(line.debugDescription)")
            #expect(!cells[2].isEmpty, "no term in \(line.debugDescription)")
            if !cells[3].isEmpty {
                #expect(Int(cells[3]).map { $0 > 0 } == true, "rank \(cells[3].debugDescription) is not a place")
            }
            #expect(Int(cells[4]).map { $0 > 0 } == true, "searched \(cells[4].debugDescription) is not a count")
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `make test 2>&1 | grep -A3 TheRankLogIsASeries`
Expected: FAIL — `aso_research.py no longer carries a DEFAULT_TERMS list` and the header assertion fails. The third test passes vacuously because `store/ranks.tsv` does not exist yet.

- [ ] **Step 3: Add the log to the tool**

In `tools/aso_research.py`, add below `PAUSE = 0.35`:

```python
RANKS = pathlib.Path(__file__).resolve().parent.parent / "store" / "ranks.tsv"
HEADER = "date\tstorefront\tterm\trank\tsearched"

# The series is only a series if both ends asked the same questions, so the
# terms live here rather than in whoever ran the command. Four of them are the
# baseline the 2026-09-20 pass set; `softcap` is the control — when it stops
# answering #1 the storefront is not being read correctly, and no other row in
# that run means anything.
DEFAULT_TERMS = [
    "claude usage", "ai usage", "codex usage", "claude code",
    "claude code usage", "ai usage tracker", "usage menu bar", "softcap",
]


def rank_row(day: str, country: str, term: str, at: int | None, searched: int) -> str:
    """One line of the log. `at` is None when the app was nowhere in `searched`."""
    return "\t".join([day, country, term, str(at) if at else "", str(searched)])


def log_rows(rows: list[str]) -> None:
    """Append, writing the header only into a file that does not have one."""
    fresh = not RANKS.exists() or RANKS.stat().st_size == 0
    RANKS.parent.mkdir(parents=True, exist_ok=True)
    with RANKS.open("a", encoding="utf-8") as file:
        if fresh:
            file.write(HEADER + "\n")
        for row in rows:
            file.write(row + "\n")
```

Add `import datetime` and `import pathlib` to the imports at the top of the file, keeping them in alphabetical order with the existing `import json`, `import plistlib`, `import sys`, `import time`, `import urllib.parse`, `import urllib.request`.

Replace the body of `main` from `mode, country, terms = ...` down to the end of the `for term in terms:` loop with:

```python
    mode, country = sys.argv[1], sys.argv[2]
    arguments = sys.argv[3:]
    logging = "--log" in arguments
    terms = [argument for argument in arguments if argument != "--log"]
    if mode == "rank" and not terms:
        terms = DEFAULT_TERMS
    if not terms:
        print(__doc__, file=sys.stderr)
        return 2
    if country not in STOREFRONTS:
        print(f"no storefront id for {country!r}; add it above", file=sys.stderr)
        return 1

    day = datetime.date.today().isoformat()
    rows: list[str] = []

    for term in terms:
        if mode == "hints":
            print(f"{term!r}: " + " | ".join(hints(term, country)))
        elif mode == "rivals":
            print(f"{term!r}")
            for place, app in enumerate(search(term, country), 1):
                print(f"  {place:2}. {app['trackName']} — {app.get('sellerName', '')}")
        elif mode == "rank":
            found = search(term, country, limit=50)
            at = next((place for place, app in enumerate(found, 1)
                       if app.get("trackId") == APP_ID), None)
            print(f"{term!r}: {'#' + str(at) if at else f'nowhere in {len(found)}'}")
            rows.append(rank_row(day, country, term, at, len(found)))
        else:
            print(f"unknown question {mode!r}", file=sys.stderr)
            return 2

    if logging and rows:
        log_rows(rows)
        print(f"{len(rows)} rows appended to {RANKS.relative_to(RANKS.parent.parent)}")
    return 0
```

Delete the now-unreachable guard `if len(sys.argv) < 4` at the top of `main` and replace it with `if len(sys.argv) < 3`, because `rank us --log` with no terms is now valid.

In the module docstring, extend the `rank` paragraph with:

```
  `--log` appends each measurement to `store/ranks.tsv` and, given no terms,
  measures `DEFAULT_TERMS`. The file is committed, so "did it move" is a diff
  rather than a thing somebody remembers.
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `make test 2>&1 | grep -A3 TheRankLogIsASeries`
Expected: PASS, three tests.

- [ ] **Step 5: Take the first measurement**

Run: `python3 tools/aso_research.py rank us --log`
Expected: eight printed lines, `softcap` at `#1` and the rest `nowhere in ~45`, then `8 rows appended to store/ranks.tsv`.

Then confirm the file: `head -3 store/ranks.tsv`

- [ ] **Step 6: Re-run the suite against the real file**

Run: `make test 2>&1 | grep -A3 TheRankLogIsASeries`
Expected: PASS — now `everyRowThatHasBeenWrittenCanBeRead` has rows to read.

- [ ] **Step 7: Commit**

```bash
git add tools/aso_research.py store/ranks.tsv \
        Packages/Core/Tests/StatusUITests/TheRankLogIsASeriesTests.swift
git commit -m "Write every rank measurement down instead of printing it

The last pass ended on measure again in a fortnight and could not: the
measurement was printed to a terminal. The terms now live in the tool, so
two runs a fortnight apart ask the same questions." \
  -- tools/aso_research.py store/ranks.tsv \
     Packages/Core/Tests/StatusUITests/TheRankLogIsASeriesTests.swift
```

---

### Task 2: The analytics reader

A one-time snapshot has been ordered from App Store Connect. It answers what ranks cannot: whether the app is shown at all, and whether the people shown it open the page. Nothing in the repository can read it.

Report names and categories are Apple's, and they change. The tool therefore **lists what exists** rather than hardcoding names this plan has not seen.

**Files:**
- Create: `tools/asc_analytics.py`
- Modify: `store/README.md` (a short section, after "Why the keywords are in English in all ten")

**Interfaces:**
- Consumes: `token()` and `call()` from `tools/push_store_metadata.py`, imported as a module. Both already exist; `call(method, path, body=None, raw=None, headers=None)` prefixes `BASE` when `path` does not start with `http` and attaches the bearer token.
- Produces: two commands — `list` (prints `category  name  id` per report) and `fetch <substring>` (prints a per-day, per-storefront summary of the matching report). No other task depends on it.

- [ ] **Step 1: Write the tool**

Create `tools/asc_analytics.py`:

```python
#!/usr/bin/env python3
"""Reads the analytics report App Store Connect was asked for.

    python3 tools/asc_analytics.py list
    python3 tools/asc_analytics.py fetch "Discovery and Engagement"

Ranks say where the app sits in an answer. This says whether anybody asked:
impressions, product page views, downloads. Until 2026-09-24 no report had ever
been requested for this app, so none of it was visible.

A request is made once and filled by Apple roughly a day later; `list` says
which reports the filled request holds. The names are Apple's and they change,
so nothing here hardcodes one — `fetch` takes any substring of a name.

Reads ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH from the environment, as the
other two tools in this directory do, and writes none of them anywhere.
"""

import collections
import csv
import gzip
import io
import sys
import urllib.request

sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))
import push_store_metadata as asc          # noqa: E402  — the token and the caller

APP_ID = "6811539739"


def requests() -> list[dict]:
    return asc.call("GET", f"/v1/apps/{APP_ID}/analyticsReportRequests?limit=20")["data"]


def reports(request_id: str) -> list[dict]:
    found, url = [], f"/v1/analyticsReportRequests/{request_id}/reports?limit=200"
    while url:
        page = asc.call("GET", url)
        found += page["data"]
        url = page.get("links", {}).get("next")
    return found


def instances(report_id: str) -> list[dict]:
    url = f"/v1/analyticsReports/{report_id}/instances?filter[granularity]=DAILY&limit=200"
    return asc.call("GET", url)["data"]


def rows(instance_id: str):
    """Every row of every segment of one daily instance.

    The segment URL is pre-signed and must be fetched without the bearer token —
    sending one is answered with a redirect that drops the signature.
    """
    for segment in asc.call("GET", f"/v1/analyticsReportInstances/{instance_id}/segments")["data"]:
        url = segment["attributes"]["url"]
        with urllib.request.urlopen(url, timeout=120) as response:
            raw = response.read()
        text = gzip.decompress(raw).decode("utf-8") if raw[:2] == b"\x1f\x8b" else raw.decode("utf-8")
        yield from csv.DictReader(io.StringIO(text), delimiter="\t")


def one_request() -> str:
    found = requests()
    if not found:
        raise SystemExit("no analytics report has been requested for this app yet")
    for request in found:
        if request["attributes"].get("stoppedDueToInactivity"):
            print(f"note: request {request['id']} was stopped for inactivity", file=sys.stderr)
    return found[0]["id"]


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    mode = sys.argv[1]
    request_id = one_request()

    if mode == "list":
        for report in reports(request_id):
            attributes = report["attributes"]
            print(f"{attributes.get('category', ''):<28} {attributes.get('name', '')}")
        return 0

    if mode == "fetch":
        if len(sys.argv) < 3:
            print("fetch needs a substring of a report name; run list first", file=sys.stderr)
            return 2
        wanted = sys.argv[2].lower()
        matching = [r for r in reports(request_id)
                    if wanted in r["attributes"].get("name", "").lower()]
        if not matching:
            print(f"no report name contains {sys.argv[2]!r}; run list", file=sys.stderr)
            return 1

        for report in matching:
            name = report["attributes"]["name"]
            print(f"\n=== {name} ===")
            totals: dict[tuple[str, str], collections.Counter] = {}
            for instance in instances(report["id"]):
                day = instance["attributes"].get("processingDate", "")
                for row in rows(instance["id"]):
                    place = row.get("Territory") or row.get("Storefront") or "—"
                    counter = totals.setdefault((day, place), collections.Counter())
                    for column, value in row.items():
                        if column in ("Impressions", "Product Page Views", "Counts",
                                      "Total Downloads", "First-Time Downloads"):
                            counter[column] += int(value or 0)
            if not totals:
                print("  the request is filled but this report has no daily instance yet")
            for (day, place), counter in sorted(totals.items()):
                numbers = "  ".join(f"{k}={v}" for k, v in sorted(counter.items()) if v)
                if numbers:
                    print(f"  {day}  {place:<6} {numbers}")
        return 0

    print(f"unknown question {mode!r}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Run `list` against the real account**

The credentials live outside the repository. Load them the way the other tools are run, then:

```bash
ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=/path/AuthKey_….p8 \
    python3 tools/asc_analytics.py list
```

Expected, if the request Apple was given on 2026-09-24 has been filled: a list of report categories and names, one per line. Expected if it has not: an empty list — the request exists but Apple has not populated it. Both are correct outcomes; an exception is not.

If the output is empty, stop here, leave the remaining steps of this task for the next day, and move to Task 3.

- [ ] **Step 3: Run `fetch` for the two reports that matter**

```bash
ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=/path/AuthKey_….p8 \
    python3 tools/asc_analytics.py fetch "Discovery and Engagement"
```

Expected: `=== <report name> ===` and then one line per day and storefront carrying `Impressions` and `Product Page Views`. Repeat with a substring matching the downloads report as `list` spells it.

- [ ] **Step 4: Document it where the other tools are documented**

Append to `store/README.md`, after the section "Why the keywords are in English in all ten":

```markdown
## Whether anybody is being shown the listing

`aso_research.py` reads the store from outside, as a shopper does. It cannot say
how often the store showed this app to somebody, or how many of those people
opened the page — and a listing that ranks nowhere and a listing that ranks and
is ignored need different work.

That comes from App Store Connect, and only if a report has been asked for. One
was, on 24 September 2026; the first had never been requested, which is why none
of this was visible before.

    python3 tools/asc_analytics.py list
    python3 tools/asc_analytics.py fetch "Discovery and Engagement"

The report names are Apple's and they change, so `list` prints them rather than
this page naming one. Credentials are the three the push tool already reads.
```

- [ ] **Step 5: Commit**

```bash
git add tools/asc_analytics.py store/README.md
git commit -m "Read the analytics report the store keeps

Ranks say where the app sits in an answer; this says whether anybody
asked. No report had ever been requested for this app, so impressions and
page views had never been visible at all." \
  -- tools/asc_analytics.py store/README.md
```

---

### Task 3: `cooldown` becomes `code`

The token `code` appears nowhere in the listing — not in a name, not in a subtitle, not in a keyword file, in any of the ten locales. `Codex` does not supply it: the store indexes words, not substrings. `claude code` is one of the four terms this work is measured against and the listing cannot match it at all.

`cooldown` is what pays for it. Nobody searches a quota tool for `cooldown`.

**Files:**
- Modify: `store/metadata/en-US/keywords.txt`, and the same file under `ru`, `es-ES`, `es-MX`, `fr-FR`, `pt-BR`, `hi`, `id`, `ar-SA`, `zh-Hans`
- Modify: `store/README.md` (one paragraph in "Why the keywords are in English in all ten")
- Modify: `docs/DECISIONS.md` (a new entry)
- Test: `Packages/Core/Tests/StatusUITests/TheListingCarriesTheWordsItIsSearchedByTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing other tasks read.

- [ ] **Step 1: Write the failing test**

Create `Packages/Core/Tests/StatusUITests/TheListingCarriesTheWordsItIsSearchedByTests.swift`:

```swift
import Testing
import Foundation
@testable import StatusUI

/// `StoreListingFitsTheStore` proves the listing is allowed. This proves it can
/// be found.
///
/// Apple indexes the name, the subtitle and the keyword field as one bag of
/// words, and matches a query by combining words from it — `claude code` needs
/// `claude` and `code` to both be in the bag. Until 2026-09-24 `code` was in
/// none of the ten: `Codex` does not supply it, because the store indexes words
/// and not substrings, and so one of the four terms this listing is measured
/// against could not be matched at all. Not poorly — at all.
@Suite struct TheListingCarriesTheWordsItIsSearchedBy {

    /// Brand words, in every storefront including the Chinese one: a product
    /// name is typed the way its maker spells it wherever the typist lives.
    private static let everywhere = ["claude", "codex", "code"]

    /// `usage` is the English query word, and the Chinese listing deliberately
    /// answers `用量` instead — `store/README.md` says why that storefront is
    /// the exception and the other nine are not.
    private static let exceptInChinese = ["usage"]

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func metadata() throws -> [String] {
        let store = repositoryRoot.appendingPathComponent("store/metadata")
        return try FileManager.default.contentsOfDirectory(atPath: store.path)
            .filter { !$0.hasPrefix(".") }
            .sorted()
    }

    private static func indexedWords(in locale: String) throws -> Set<String> {
        let store = repositoryRoot.appendingPathComponent("store/metadata/\(locale)")
        let text = try ["name", "subtitle", "keywords"].map {
            try String(contentsOf: store.appendingPathComponent("\($0).txt"), encoding: .utf8)
        }.joined(separator: " ").lowercased()
        return Set(text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
    }

    @Test func everyListingCanAnswerTheTermsItIsMeasuredBy() throws {
        for locale in try Self.metadata() {
            let words = try Self.indexedWords(in: locale)
            var required = Self.everywhere
            if locale != "zh-Hans" { required += Self.exceptInChinese }
            for word in required {
                #expect(words.contains(word), """
                    \(locale) indexes no \"\(word)\" — the name, the subtitle and \
                    the keywords together are what a query is matched against, \
                    and a query containing \"\(word)\" cannot match this listing
                    """)
            }
        }
    }

    /// The word that paid for `code`. Kept as a test so it is not quietly
    /// re-added the next time somebody has nine spare characters.
    @Test func nothingSpendsTheFieldOnCooldown() throws {
        for locale in try Self.metadata() {
            let words = try Self.indexedWords(in: locale)
            #expect(!words.contains("cooldown"), """
                \(locale) spends nine characters on \"cooldown\", which nobody \
                searches a quota tool for; see docs/DECISIONS.md for 2026-09-24
                """)
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `make test 2>&1 | grep -A5 TheListingCarriesTheWordsItIsSearchedBy`
Expected: FAIL — ten failures saying `<locale> indexes no "code"`, and nine saying `<locale> spends nine characters on "cooldown"` (`zh-Hans` has none to spend).

- [ ] **Step 3: Make the swap**

Nine locales drop `cooldown` and all ten gain `code`. `zh-Hans` has no `cooldown`, so it only gains.

```bash
cd /path/to/the/checkout
python3 - <<'PY'
import pathlib
for directory in sorted(p for p in pathlib.Path("store/metadata").iterdir() if p.is_dir()):
    file = directory / "keywords.txt"
    words = [w.strip() for w in file.read_text(encoding="utf-8").strip().split(",")]
    words = [w for w in words if w != "cooldown"]
    if "code" not in words:
        words.append("code")
    new = ",".join(words)
    assert len(new.encode("utf-16-le")) // 2 <= 100, f"{directory.name} is {new}"
    file.write_text(new + "\n", encoding="utf-8")
    print(f"{directory.name:<8} {len(new):>3}  {new}")
PY
```

Expected: ten lines, the longest 95 characters, `zh-Hans` at 99.

- [ ] **Step 4: Run the test to verify it passes**

Run: `make test 2>&1 | grep -A5 "TheListingCarriesTheWordsItIsSearchedBy\|StoreListingFitsTheStore"`
Expected: PASS for both suites. `StoreListingFitsTheStore` matters here too — it holds the hundred-character limit, the no-duplicate rule and the rule that a keyword may not repeat a word already in the name or subtitle. `code` is in no name (`Codex` is a different word) and no subtitle, so it passes; if it did not, the swap is wrong rather than the test.

- [ ] **Step 5: Say why, where the reasoning lives**

In `store/README.md`, inside the section "Why the keywords are in English in all ten", after the paragraph that begins "The questions can be asked again", insert:

```markdown
One of those four questions could never have been answered. Asked again on 24
September 2026, the listing indexed no `code` at all — not in a name, not in a
subtitle, not in a keyword file, in any of the ten. `Codex` does not supply it:
the store indexes words, not substrings, so `claude code` had nothing to match.
`cooldown` paid for it, being a word nobody searches a quota tool for. The spare
characters left over are left spare; filling them with a guess is how `cooldown`
got there.
```

Then add an entry to `docs/DECISIONS.md`, dated 2026-09-24, following the file's existing three-part shape — what was decided, why, what it cost:

- **Decided:** every keyword file carries `code`; nine of them stop carrying `cooldown`.
- **Why:** `claude code` is one of the four terms the 2026-09-20 pass set as the baseline, and the listing indexed no `code`, so the term could not be matched. Verified by reading the indexed words out of the three fields Apple combines.
- **Cost:** `cooldown` is gone, and if anyone does search it the listing no longer answers. Nine characters of the hundred are spare in `en-US` and deliberately unspent, so the field is not full when the next measured reason to add a word arrives.

Do not rewrite the 2026-09-20 entry. A reversed decision gets a new entry referring to the old one.

- [ ] **Step 6: Commit**

```bash
git add store/metadata store/README.md docs/DECISIONS.md \
        Packages/Core/Tests/StatusUITests/TheListingCarriesTheWordsItIsSearchedByTests.swift
git commit -m "Let the listing answer claude code

The token code was in none of the ten listings. Codex does not supply it:
the store indexes words, not substrings, so one of the four terms this
work is measured against could not be matched at all. Cooldown paid for
it, being a word nobody searches a quota tool for." \
  -- store/metadata store/README.md docs/DECISIONS.md \
     Packages/Core/Tests/StatusUITests/TheListingCarriesTheWordsItIsSearchedByTests.swift
```

---

### Task 4: The moment worth asking at

The app has no ratings. The app in first place for `claude usage` has five, and every other app in the first twelve has none — so five ratings is the front of this field.

This task is the decision only: a pure type in `Monitoring`, with no StoreKit and no strings, and the two settings it reads. Task 5 makes the call.

**Files:**
- Create: `Packages/Core/Sources/Monitoring/RatingMoment.swift`
- Modify: `Packages/Core/Sources/Preferences/Preferences.swift` (two fields, two defaults, two decoder lines)
- Test: `Packages/Core/Tests/MonitoringTests/AskingForARatingWaitsForAGoodMomentTests.swift`

**Interfaces:**
- Consumes: `Preferences` from the `Preferences` module.
- Produces:
  - `Preferences.firstLaunch: Date?` — when the app first ran. `nil` means it has not been recorded yet.
  - `Preferences.ratingAsked: Date?` — when StoreKit was asked. `nil` means never.
  - `RatingMoment.Conditions(hasAccount: Bool, warningFired: Bool, firstLaunch: Date?, ratingAsked: Date?)`
  - `RatingMoment.shouldAsk(_ conditions: Conditions, now: Date) -> Bool`
  - `RatingMoment.settlingIn: TimeInterval` — five days, in seconds.

- [ ] **Step 1: Write the failing test**

Create `Packages/Core/Tests/MonitoringTests/AskingForARatingWaitsForAGoodMomentTests.swift`:

```swift
import Testing
import Foundation
@testable import Monitoring

/// A menu-bar utility that interrupts is a menu-bar utility that gets quit, so
/// the interruption is spent once — after the app has done the thing it exists
/// to do — or not at all.
///
/// Quiet hours are not checked here and do not need to be: `ThresholdTracker`
/// emits no event at all while they are in force, so a warning that fired is
/// already a warning that fired at an hour the person allowed.
@Suite struct AskingForARatingWaitsForAGoodMoment {

    private static let installed = Date(timeIntervalSince1970: 1_700_000_000)
    private static let settled = installed.addingTimeInterval(RatingMoment.settlingIn + 1)

    private static func conditions(
        hasAccount: Bool = true,
        warningFired: Bool = true,
        firstLaunch: Date? = installed,
        ratingAsked: Date? = nil
    ) -> RatingMoment.Conditions {
        RatingMoment.Conditions(hasAccount: hasAccount, warningFired: warningFired,
                                firstLaunch: firstLaunch, ratingAsked: ratingAsked)
    }

    @Test func itAsksOnceTheAppHasWarnedSomebodyInTime() {
        #expect(RatingMoment.shouldAsk(Self.conditions(), now: Self.settled))
    }

    @Test func itDoesNotAskBeforeTheAppHasWarnedAnybody() {
        #expect(!RatingMoment.shouldAsk(Self.conditions(warningFired: false), now: Self.settled))
    }

    @Test func itDoesNotAskSomebodyWithNoAccountConnected() {
        #expect(!RatingMoment.shouldAsk(Self.conditions(hasAccount: false), now: Self.settled))
    }

    /// Five days, because a rating left on the first afternoon is a rating for
    /// the icon.
    @Test func itDoesNotAskInTheFirstFiveDays() {
        let early = Self.installed.addingTimeInterval(RatingMoment.settlingIn - 1)
        #expect(!RatingMoment.shouldAsk(Self.conditions(), now: early))
    }

    @Test func itDoesNotAskBeforeItKnowsWhenTheAppWasInstalled() {
        #expect(!RatingMoment.shouldAsk(Self.conditions(firstLaunch: nil), now: Self.settled))
    }

    @Test func itNeverAsksTwice() {
        let asked = Self.conditions(ratingAsked: Self.settled)
        let later = Self.settled.addingTimeInterval(365 * 24 * 60 * 60)
        #expect(!RatingMoment.shouldAsk(asked, now: later))
    }

    /// A clock that has gone backwards — a restored machine, a corrected time
    /// zone — must not read as five days elapsed.
    @Test func aClockThatWentBackwardsIsNotFiveDays() {
        let before = Self.installed.addingTimeInterval(-60)
        #expect(!RatingMoment.shouldAsk(Self.conditions(), now: before))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `make test 2>&1 | grep -A3 AskingForARatingWaitsForAGoodMoment`
Expected: FAIL — the build fails, `cannot find 'RatingMoment' in scope`.

- [ ] **Step 3: Write the decision**

Create `Packages/Core/Sources/Monitoring/RatingMoment.swift`:

```swift
import Foundation

/// Whether this is a moment to ask for a rating.
///
/// The app shipped with none, in a field where the app in first place has five
/// — so the first few matter more than any wording in the listing does. What
/// stops that from being a reason to nag is that there is exactly one ask, and
/// it is spent after the app has already been useful: an account connected, the
/// first days past, and a limit warning actually delivered.
///
/// No StoreKit here and no text: the decision is testable and portable, the call
/// is three lines in the App target, and `CoreStaysPortable` holds the line
/// between them.
public enum RatingMoment {

    /// Five days. A rating left on the first afternoon is a rating for the icon.
    public static let settlingIn: TimeInterval = 5 * 24 * 60 * 60

    public struct Conditions: Sendable, Equatable {
        public let hasAccount: Bool
        /// A threshold warning has been delivered at least once this run.
        /// `ThresholdTracker` emits nothing during quiet hours, so this being
        /// true already means the app spoke at an hour the person allowed.
        public let warningFired: Bool
        public let firstLaunch: Date?
        public let ratingAsked: Date?

        public init(hasAccount: Bool, warningFired: Bool, firstLaunch: Date?, ratingAsked: Date?) {
            self.hasAccount = hasAccount
            self.warningFired = warningFired
            self.firstLaunch = firstLaunch
            self.ratingAsked = ratingAsked
        }
    }

    public static func shouldAsk(_ conditions: Conditions, now: Date) -> Bool {
        guard conditions.ratingAsked == nil,
              conditions.hasAccount,
              conditions.warningFired,
              let installed = conditions.firstLaunch
        else { return false }
        // `timeIntervalSince` rather than a comparison, so a clock that has gone
        // backwards reads as a negative interval and not as time elapsed.
        return now.timeIntervalSince(installed) >= settlingIn
    }
}
```

- [ ] **Step 4: Add the two settings**

In `Packages/Core/Sources/Preferences/Preferences.swift`, after the `lastUpdateCheck` declaration in the `// Updates` group, add a new group:

```swift
    // Rating
    /// When the app first ran. `nil` until the first launch records it, which
    /// is also why nothing is asked of somebody upgrading from a build that
    /// never wrote it — they are treated as installed today, and wait.
    public var firstLaunch: Date?
    /// When StoreKit was asked for a rating. `nil` means never, and it is set
    /// whether or not Apple chose to show anything: the app has spent its ask.
    public var ratingAsked: Date?
```

Add both to `Preferences.defaults`, after `checksForUpdates` and `lastUpdateCheck` in the existing argument order:

```swift
        firstLaunch: nil,
        ratingAsked: nil,
```

Add both to the hand-written `init(from decoder:)`, beside `lastUpdateCheck`:

```swift
        firstLaunch          = readOptional(.firstLaunch, fallback.firstLaunch)
        ratingAsked          = readOptional(.ratingAsked, fallback.ratingAsked)
```

The decoder reads field by field precisely so that adding these two does not discard everybody's other settings on upgrade. `CodingKeys` is synthesised from the stored properties, so nothing else is needed.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `make test`
Expected: PASS throughout — the seven new tests, and `PreferencesTests` unchanged. If `PreferencesTests` constructs a `Preferences` with the full argument list, it needs the two new arguments; add them as `nil`.

- [ ] **Step 6: Commit**

```bash
git add Packages/Core/Sources/Monitoring/RatingMoment.swift \
        Packages/Core/Sources/Preferences/Preferences.swift \
        Packages/Core/Tests/MonitoringTests/AskingForARatingWaitsForAGoodMomentTests.swift
git commit -m "Work out when asking for a rating would be fair

One ask, spent after the app has already been useful: an account
connected, five days past, and a warning actually delivered. Quiet hours
need no check here — the tracker emits nothing while they hold." \
  -- Packages/Core/Sources/Monitoring/RatingMoment.swift \
     Packages/Core/Sources/Preferences/Preferences.swift \
     Packages/Core/Tests/MonitoringTests/AskingForARatingWaitsForAGoodMomentTests.swift
```

---

### Task 5: Making the ask

Three lines of StoreKit, in the App target, behind `#if APPSTORE`. The direct-download build cannot be rated on the App Store, and asking there would open a page for a product the person did not install.

**`AppModel` cannot save settings.** Its `preferences` is `@Published var preferences: Preferences = .defaults`, pushed in by `SoftcapApp`'s subscription to `PreferencesModel.$value` (`App/SoftcapApp.swift:61-66`); the only object that writes is `PreferencesModel.update(_:)`. The app already has a pattern for "something happened deep in the model, record it in settings" — `updates.recordCheck`, set at `App/SoftcapApp.swift:109-111`:

```swift
            updates.recordCheck = { [preferences] moment in
                preferences.update { $0.lastUpdateCheck = moment }
            }
```

This task follows it exactly: `AppModel` reports that a warning was delivered, and the delegate — which owns the settings — decides and asks.

**Files:**
- Create: `App/RatingPrompt.swift`
- Modify: `App/AppModel.swift` (one callback property; four lines in `poll()`)
- Modify: `App/SoftcapApp.swift` (record the first launch after `preferences.load()`; wire the callback)

**Interfaces:**
- Consumes: `RatingMoment.Conditions`, `RatingMoment.shouldAsk(_:now:)`, `RatingMoment.settlingIn`, `Preferences.firstLaunch`, `Preferences.ratingAsked` from Task 4. `PreferencesModel.update(_:)` and `PreferencesModel.value` from `App/PreferencesModel.swift`.
- Produces:
  - `AppModel.warningDelivered: ((Bool) -> Void)?` — called on the main actor after a `.crossed` notification has been posted, with whether at least one account produced a reading.
  - `RatingPrompt.considerAsking(hasAccount: Bool)`.

**Why this task opens with code and not with a failing test.** `make test` runs `swift test` inside `Packages/Core`, which cannot see the `App` target; the only App sources under test are the three `tools/test_authentication.py` stages into a temporary package, and none of them is this. Every decision worth asserting was therefore put in Task 4, where it is tested — `shouldAsk` and its six rules. What is left here is wiring: a callback, a struct that forwards to it, and three lines at startup. It is verified by the two builds in Step 4, and the lane that actually compiles the StoreKit call is the second of them.

- [ ] **Step 1: Report the moment from `AppModel`**

In `App/AppModel.swift`, beside the other callbacks the delegate fills in (`login.didAddAccount` is set at `App/SoftcapApp.swift:68`), add the property:

```swift
    /// Called after a threshold warning has actually been delivered, with
    /// whether any account produced a reading.
    ///
    /// The model cannot act on it: settings are owned by `PreferencesModel` and
    /// arrive here already decided, so whether this is a moment to ask for a
    /// rating is the delegate's to answer. Same shape as `updates.recordCheck`.
    var warningDelivered: ((Bool) -> Void)?
```

In `poll()`, replace the notification block at lines 619-624:

```swift
        let events = tracker.events(for: result, now: Date())
        // The reading is fed to the tracker even with notifications off:
        // otherwise turning them on would deliver a batch of stale events.
        if preferences.notificationsEnabled {
            for event in events { post(event) }
        }
```

with:

```swift
        let events = tracker.events(for: result, now: Date())
        // The reading is fed to the tracker even with notifications off:
        // otherwise turning them on would deliver a batch of stale events.
        var warned = false
        if preferences.notificationsEnabled {
            for event in events {
                post(event)
                // A recovery deliberately does not count. Being told a limit
                // came back is pleasant; being warned before running out is the
                // thing the app was installed for, and that is the moment worth
                // spending an interruption after.
                if case .crossed = event.kind { warned = true }
            }
        }
        if warned {
            warningDelivered?(result.contains { $0.failure == nil })
        }
```

Demo accounts cannot trigger this: the samples are never fed to the tracker, for the reason given in the comment at line 391, so they produce no events to post.

- [ ] **Step 2: Write the prompt**

Create `App/RatingPrompt.swift`:

```swift
import Foundation
import Monitoring
import Preferences
#if APPSTORE
import StoreKit
#endif

/// Asks the App Store for a rating, at most once in the life of an install.
///
/// The app shipped with none, in a field where the app in first place has five,
/// so the first few ratings are worth more than any wording in the listing. What
/// keeps that from being a reason to nag is that there is exactly one ask, and
/// `RatingMoment` — which is tested, and lives in Core — decides when it is
/// fair to spend it.
///
/// The direct-download build never asks. It cannot be rated on the App Store,
/// and sending somebody who installed a .dmg to a store page for a product they
/// do not have there is worse than never asking at all.
@MainActor
struct RatingPrompt {
    let preferences: PreferencesModel

    func considerAsking(hasAccount: Bool) {
        #if APPSTORE
        let conditions = RatingMoment.Conditions(
            hasAccount: hasAccount,
            warningFired: true,
            firstLaunch: preferences.value.firstLaunch,
            ratingAsked: preferences.value.ratingAsked
        )
        guard RatingMoment.shouldAsk(conditions, now: Date()) else { return }

        // Recorded before the ask, not after. Apple decides whether anything is
        // shown and tells the app nothing about it, so the only fact the app can
        // honestly write down is that it has spent its one request.
        preferences.update { $0.ratingAsked = Date() }
        SKStoreReviewController.requestReview()
        #endif
    }
}
```

If `SKStoreReviewController.requestReview()` raises a deprecation warning that `make lint` refuses, replace that one line with StoreKit 2's `Task { await AppStore.requestReview() }` and leave everything else as written. Do not silence the warning.

- [ ] **Step 3: Wire it up at startup**

In `App/SoftcapApp.swift`, immediately after `await preferences.load()` at line 108 and before the `updates.recordCheck` assignment, add:

```swift
            // Recorded once and never revised. The wait before the app asks for
            // anything has to start somewhere, and for an install that predates
            // this setting the only honest answer is today — so an upgrade waits
            // the full five days rather than asking on the afternoon it lands.
            if preferences.value.firstLaunch == nil {
                preferences.update { $0.firstLaunch = Date() }
            }
            let rating = RatingPrompt(preferences: preferences)
            model.warningDelivered = { hasAccount in
                rating.considerAsking(hasAccount: hasAccount)
            }
```

- [ ] **Step 4: Build both lanes**

Run: `make build`
Expected: builds clean. This is the direct-download lane, so the `#if APPSTORE` body is compiled out — it proves the call site compiles, not the call.

Run: `make archive-appstore`
Expected: builds clean. This is the lane that compiles the StoreKit call. A mistake inside `#if APPSTORE` is invisible until this runs, which is the whole reason this step is separate.

- [ ] **Step 5: Run the suite**

Run: `make test`
Expected: PASS. `CoreStaysPortable` is the one to watch — it fails if StoreKit reached `Monitoring`, which would mean the decision and the call got mixed together.

- [ ] **Step 6: Say what was decided**

Add an entry to `docs/DECISIONS.md` dated 2026-09-24:

- **Decided:** the App Store build asks for a rating exactly once, after an account is connected, five days have passed since first launch, and a threshold warning has actually been delivered.
- **Why:** the app has no ratings and the app in first place for `claude usage` has five, so the first handful of ratings is worth more than any wording in the listing. Measured 2026-09-24: eleven of the twelve apps answering that term have none at all.
- **Cost:** one interruption, in a menu-bar utility where interruptions are the reason people quit — spent at the moment the app has just been useful, or never. The direct-download build never asks, so ratings can only come from the store half of the audience.

- [ ] **Step 7: Commit**

```bash
git add App/RatingPrompt.swift App/AppModel.swift App/SoftcapApp.swift docs/DECISIONS.md
git commit -m "Ask for a rating once, after the app has earned it

The store copy asks when a warning has just been delivered, an account is
connected and the first five days are past. The direct-download copy
never asks: it cannot be rated there." \
  -- App/RatingPrompt.swift App/AppModel.swift App/SoftcapApp.swift docs/DECISIONS.md
```

The new file has to reach the target as well as the disk: `App/` is built from `project.yml` through XcodeGen (`make project`), so confirm `App/RatingPrompt.swift` is picked up by the App target's source glob rather than needing to be listed. `make build` in Step 4 is what proves it.

---

### Task 6: The description stops saying Copilot is unsupported

**Precondition, and it is a real one:** this task does not start until a live GitHub Copilot account with an active subscription has signed in and shown a real quota reading. A description promising a provider the app cannot actually reach is worse than one that omits it. If no such account exists yet, leave this task undone and say so — it rides the version after.

**Files:**
- Modify: `store/metadata/en-US/description.txt`, and the same file under the other nine locales
- Modify: `site/index.html` and its nine language variants (hero text), plus the FAQ entry that says Copilot is not supported

**Interfaces:**
- Consumes: nothing.
- Produces: nothing.

- [ ] **Step 1: Find every place that says it is unsupported**

Run: `grep -rn -i "copilot" store/metadata site --include=*.txt --include=*.html | grep -i "not\|unsupported\|later\|no "`
Expected: a list covering the store descriptions, the homepage hero and the FAQ. Work from that list; this step exists because the earlier session's notes record the hero and the FAQ but may not be complete.

- [ ] **Step 2: Change the two lines in each description that enumerate the services**

Every one of the ten descriptions has the same two lines, and only these two name the services:

- **Line 1**, the opening sentence. In `en-US` it reads:

  > Softcap shows how much of your Claude Code and OpenAI Codex subscriptions you have left, in the menu bar, before you run out in the middle of something.

  becoming:

  > Softcap shows how much of your Claude Code, OpenAI Codex and GitHub Copilot subscriptions you have left, in the menu bar, before you run out in the middle of something.

- **Line 6**, the paragraph under the `SEVERAL ACCOUNTS AT ONCE` heading. In `en-US` it opens:

  > Claude and Codex accounts side by side, as many as you have.

  becoming:

  > Claude, Codex and Copilot accounts side by side, as many as you have.

Make the same two changes in the other nine, translating rather than appending English — a mixed-language file is worse than either language alone. The line numbers hold in all ten, `ar-SA` and `zh-Hans` included; verify with `sed -n '1p;6p' store/metadata/<locale>/description.txt` before editing rather than trusting the count.

- [ ] **Step 3: Check the lengths still fit**

Run: `make test 2>&1 | grep -A5 StoreListingFitsTheStore`
Expected: PASS. The description limit is 4000 UTF-16 units and the Devanagari and Arabic listings are the ones with the least headroom, so this is where a change that looks safe is refused.

- [ ] **Step 4: Fix the site**

Change the hero text and the FAQ entry found in Step 1, in all ten language variants. Then run: `make test`
Expected: PASS — `LandingMatchesApp` and `LandingQuotesTheCode` compare the site against the app and will fail if one side now claims something the other does not.

- [ ] **Step 5: Commit**

```bash
git add store/metadata site
git commit -m "Stop saying Copilot is unsupported

The provider has been written and verified against a live account; the
store description, the hero and the FAQ all still said it was not
supported." \
  -- store/metadata site
```

---

## Sequence

Tasks 1 and 2 are measurement and wait on nothing. Task 3 can be done at any time — it ships with the next version whenever that is. Tasks 4 and 5 are the product change.

**The one ordering constraint:** the listing must be measured on the day 0.1.36 is approved, before the next version is pushed. That row is the baseline for the new name, and without it the name change and the keyword change cannot be told apart.

```
now            Task 1, Task 3, Task 4, Task 5
+1 day         Task 2 steps 2-5, once Apple has filled the report
0.1.36 approved   python3 tools/aso_research.py rank us --log      ← the baseline row
then           push the next version with Tasks 3 and 5 in it
+3 days        python3 tools/aso_research.py rank us --log
+14 days       python3 tools/aso_research.py rank us --log
```

Task 6 joins the push if a live Copilot account has verified the flow by then, and waits for the version after if it has not.

## What tells us it worked

`store/ranks.tsv` holds a row for `claude usage` in `us` on the day 0.1.36 is approved and another a fortnight later. If the second is a number and the first is not, the model behind both passes — that the name carries the search — is right. If both are empty, it is wrong, and `asc_analytics.py` says whether the app is being shown at all, which is the next question either way.
