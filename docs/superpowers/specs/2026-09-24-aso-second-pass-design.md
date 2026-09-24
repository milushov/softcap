# The second pass at being found

## What was actually wrong

The listing written on 20 September — the name that carries the search terms,
the ten locales, the subtitle — is not in the App Store. It rides version
0.1.36, which has been `IN_REVIEW` since 21 September. What the store serves is
0.1.25: one locale, and an app called `Softcap`.

So the ranks measured on 24 September — nowhere in the first fifty for `claude
usage`, `ai usage`, `codex usage`, `claude code`, first for `softcap` — are the
same ranks as the baseline, measured against the same listing. Nothing has been
tested yet. The work did not fail; it has not shipped.

That is the first half of this document: do not re-do the research, ship what it
already concluded.

## What the field looks like now

The second half is what a fresh look does find.

Twelve apps answer `claude usage` in the US Mac storefront. The one in first
place has five ratings. Every other app in the first twelve has none. One of
them misspells Claude in its own name and still ranks; another has not been
updated since October 2025 and still ranks.

A field where nobody has ratings is a field where nothing is being ranked by
downloads, because there are no downloads to rank by. What separates first place
from nowhere is the text, and the text that matters is the name: every app in
the first ten for `claude usage` and for `ai usage tracker` carries the words of
the query in its name. `Softcap` carries them in its keywords, and that was not
enough for fiftieth place.

This is the argument the 20 September research already made. It is now measured
rather than reasoned, and it points at the version sitting in review.

## The gap that research missed

The token `code` does not appear anywhere in the listing — not in the name, not
in the subtitle, not in the keywords, in any of the ten locales. `Codex` does not
supply it: the store indexes words, not substrings.

`claude code` is one of the four terms this work is measured against, and the
listing cannot match it. Not poorly — at all.

`copilot` is absent too, and that one stays absent on purpose. In the US Mac
storefront `copilot usage` returns pilot logbooks and avionics; the storefront
completes `copilot` to Microsoft's assistant and to car navigation. The provider
now exists in the app, but there is no search traffic behind the word, and a
keyword that brings an audience looking for something else costs a slot and
returns nothing.

## What changes

### A rank log instead of a memory

`aso_research.py rank` gains `--log`, which appends each measurement to
`store/ranks.tsv`: date, storefront, term, position, and the depth searched when
the app was not found. The file is committed, so the series lives in the history
and "did it move" is a diff.

The previous pass ended on the sentence "measure again in a fortnight". Nobody
could, because a measurement that is not written down is not a series. One
default set of terms ships with the flag, so two runs a fortnight apart are
comparable: `claude usage`, `ai usage`, `codex usage`, `claude code`, `claude
code usage`, `ai usage tracker`, `usage menu bar`, `softcap`.

### Reading what the store already knows

A one-time analytics snapshot has been ordered from App Store Connect. It
answers what ranks cannot: whether the app is shown at all, and whether the
people shown it open the page.

`tools/asc_analytics.py` fetches the finished report and prints the three
numbers that matter — impressions, product page views, downloads — by day and by
storefront. It reads `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_PATH` from the
environment, as `push_store_metadata.py` and `asc_preflight.py` already do, and
it writes no credential anywhere.

Ranks say where we sit in an answer. This says whether anyone asked.

### `cooldown` becomes `code`

In all ten keyword files, `cooldown` is dropped and `code` is added. Nobody
searches a quota tool for `cooldown`; `claude code` is a term the storefront
completes and the listing cannot currently match.

The arithmetic holds everywhere — the longest result is 95 of the 100 characters
allowed, and `zh-Hans`, which has no `cooldown` to drop, reaches 99.
`StoreListingFitsTheStore` proves it rather than this paragraph.

The spare characters are left spare. Filling them with a guess is how
`cooldown` got there.

### The description says Copilot is supported

The app supports GitHub Copilot; the store description, the homepage hero and
the FAQ all still say it does not. This is a conversion fix, not a ranking one:
it is read by someone already on the page, deciding.

It ships only once a live Copilot account has verified the flow end to end. A
description that promises a provider the app cannot actually reach is worse than
one that omits it.

### One request for a rating, after the app has earned it

The app has no ratings. Five would take it to the front of this field.

`SKStoreReviewController` is asked once, and only when all of these hold:

- the build is the App Store one; the direct-download build cannot be rated
  there, and asking would be a dead end
- at least one account is connected
- at least five days have passed since first launch
- at least one limit warning has already fired — the moment the app did the
  thing it exists to do
- quiet hours are not in effect
- it has never been asked before on this Mac

The flag that records the asking lives in preferences, beside the rest of the
app's state. A menu-bar utility that interrupts is a menu-bar utility that gets
quit, so the interruption is spent once, after a success, or not at all.

## What is deliberately not done

**The name is not touched.** `Softcap: Claude & Codex Usage` has not been in the
store for a single day. Changing a name twice before measuring the first change
discards the indexing and buys no knowledge. If `claude usage` rises in a
fortnight and `claude code` does not, that is evidence that keywords carry less
weight than the name for a phrase, and the name can be revisited holding it.

**The keywords stay English.** The 20 September finding stands, and was checked
again: the translated words lead to screen-time limiters, fuel gauges, parcel
tracking and crypto wallets. Chinese remains the exception it already is.

**Nothing is pulled from review.** Taking 0.1.36 out to improve it costs another
review cycle and delays the first listing that can work at all. It is far better
than what is live; it should go live.

**No keyword is spent on `copilot`, `cursor` or `token tracker`.** Checked:
polluted or empty.

## Sequence

1. Land the rank log and the analytics reader. Both are measurement; neither
   waits on Apple.
2. Read the snapshot when it arrives, roughly a day after the order.
3. When 0.1.36 is approved, measure the same day. That row is the baseline for
   the new name.
4. Ship the next version with the keyword swap and the rating request. Not
   before step 3 — the baseline row has to exist first, or the two changes
   cannot be told apart.
5. Measure again three days and a fortnight after approval.

The Copilot description edit joins step 4 if a live account has verified the
flow by then, and waits for the version after if it has not.

## How we will know

`store/ranks.tsv` holds a row for `claude usage` in `us` on the day 0.1.36 is
approved, and another a fortnight later. If the second is a number and the first
is not, the model behind both passes — that the name carries the search — is
right. If both say nowhere, it is wrong, and the analytics snapshot will say
whether the app is being shown at all, which is the next question either way.

Each of the four decisions above that survives implementation earns an entry in
`docs/DECISIONS.md`: what was decided, why, and what it cost.
