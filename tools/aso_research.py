#!/usr/bin/env python3
"""Asks the App Store what people type, and what already answers them.

    python3 tools/aso_research.py hints ru claude "claude code" лимит
    python3 tools/aso_research.py rivals us "claude usage"
    python3 tools/aso_research.py rank us "claude usage" "ai usage" "codex usage"

Three questions, two endpoints, no key:

  `hints` — what the storefront completes a prefix into. Apple publishes no
  search volumes, and this is the closest thing anybody outside it can read:
  the completions are ordered by how often that storefront sees them. It is
  what `store/metadata` is built on, and what the 2026-09-20 entry in
  docs/DECISIONS.md quotes. The honest caveat is written down there too — the
  hints index is the phone store's, because the Mac store has none of its own,
  so this measures what people search for and not what they search for on a
  Mac.

  `rivals` — what the Mac App Store actually returns for a term today. Titles
  are the useful part: every app that ranks for `ai usage` has the words in its
  name, which is the argument for spending the name's thirty characters on them.

  `rank` — where this app sits for a term, or that it is nowhere in the first
  fifty. Run it before changing the listing and a fortnight after; the listing
  is a guess until this says otherwise.

Storefront identifiers are Apple's own. The country code is the one the store
uses, not the language — `sa` and `ae` are both Arabic, and they do not answer
the same.
"""

import json
import plistlib
import sys
import time
import urllib.parse
import urllib.request

APP_ID = 6811539739

STOREFRONTS = {
    "us": 143441, "gb": 143444, "ca": 143455, "au": 143460,
    "ru": 143469, "es": 143454, "mx": 143468, "ar": 143505, "co": 143501,
    "fr": 143442, "br": 143503, "pt": 143453,
    "in": 143467, "id": 143476, "sa": 143479, "ae": 143481, "eg": 143516,
    "cn": 143465, "tw": 143470, "hk": 143463, "sg": 143464, "bd": 143490,
    "de": 143443, "jp": 143462, "tr": 143480, "ng": 143561, "pk": 143477,
}

PAUSE = 0.35            # both endpoints are Apple's, and neither is documented


def hints(term: str, country: str) -> list[str]:
    url = ("https://search.itunes.apple.com/WebObjects/MZSearchHints.woa/wa/hints"
           f"?clientApplication=Software&term={urllib.parse.quote(term)}")
    request = urllib.request.Request(url)
    request.add_header("X-Apple-Store-Front", f"{STOREFRONTS[country]}-1,29")
    request.add_header("User-Agent", "iTunes/12.12 (Macintosh; OS X 14.0)")
    with urllib.request.urlopen(request, timeout=30) as response:
        found = plistlib.loads(response.read())
    time.sleep(PAUSE)
    return [hint["term"] for hint in found.get("hints", [])]


def search(term: str, country: str, limit: int = 10) -> list[dict]:
    url = "https://itunes.apple.com/search?" + urllib.parse.urlencode(
        {"term": term, "country": country, "entity": "macSoftware", "limit": limit})
    request = urllib.request.Request(url, headers={"User-Agent": "iTunes/12.12"})
    with urllib.request.urlopen(request, timeout=30) as response:
        found = json.load(response)
    time.sleep(PAUSE)
    return found.get("results", [])


def main() -> int:
    if len(sys.argv) < 4:
        print(__doc__, file=sys.stderr)
        return 2
    mode, country, terms = sys.argv[1], sys.argv[2], sys.argv[3:]
    if country not in STOREFRONTS:
        print(f"no storefront id for {country!r}; add it above", file=sys.stderr)
        return 1

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
        else:
            print(f"unknown question {mode!r}", file=sys.stderr)
            return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
