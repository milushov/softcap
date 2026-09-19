# The App Store listing

Ten listings, one per storefront language, written as plain files so a change to
one of them is a diff rather than a form somebody filled in from memory.

    store/metadata/<locale>/name.txt              ≤ 30 characters
                            subtitle.txt          ≤ 30
                            keywords.txt          ≤ 100, comma-separated
                            description.txt       ≤ 4000
                            promotional_text.txt  ≤ 170
                            whats_new.txt         ≤ 4000

`StoreListingFitsTheStore` holds every one of those limits, so a description
that has grown past four thousand characters fails the suite rather than the
upload.

Sending it:

    ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=/path/AuthKey_….p8 \
        python3 tools/push_store_metadata.py --version 0.1.28 \
            --screenshots build-shots/store

The screenshots come from `python3 tools/store_screenshots.py`, which
photographs the app in each of its languages — `make screenshots` builds what it
photographs. Neither script submits anything for review.

## Why the keywords are in English in all ten

Apple gives no search-volume figures, but the store completes what people type,
and those completions are ordered by how often the storefront sees them. Read in
every storefront this app is localised for, in September 2026, they say the same
thing: the audience for a Claude Code and Codex usage monitor searches in
English wherever it lives.

The questions can be asked again — `python3 tools/aso_research.py hints ru
клод` for the completions, `rivals us "claude usage"` for what answers a term
today, `rank us "claude usage"` for where this app sits in the answer. On the
day the listing was written, `rank` said *nowhere in the first fifty* for
`claude usage`, `ai usage`, `codex usage` and `claude code`, and first for
`softcap`. That is the number this work is measured against.

In the Russian storefront `claude code`, `ai usage tracker` and `codex usage`
all complete; `клод код` completes to nothing at all, `лимит` completes to
screen-time apps and `токен` to crypto wallets. Spanish `límite`, French
`limite` and Portuguese `limite` all lead to screen-time limiters; `consumo` and
`consommation` lead to fuel and electricity meters; `rastreador` and
`seguimiento` to parcel tracking. Indonesian `kuota` is mobile data. Arabic
`متتبع` is habit and calorie trackers. Every one of those words is the right
translation and the wrong keyword: it would put this app in a queue behind a
hundred apps that are actually about that, for an audience that is not looking
for it.

Chinese is the exception, and is treated as one. `用量`, `额度`, `监控` and
`菜单栏` are live in that storefront — `用量追踪器` completes, and a competitor
ships under a Chinese name — so the Chinese listing carries Chinese keywords and
a Chinese subtitle.

So: the name and the keywords carry the English terms the store is actually
asked for, and the subtitle and the description are written in the reader's
language, because those are what a person reads once the search has already
found us. The whole reasoning, with the counts, is in `docs/DECISIONS.md` under
2026-09-20.

## Why there is no Bengali

The app speaks ten languages; App Store Connect offers metadata in
thirty-nine, and Bengali is not among them. A Bengali speaker in the Bangladesh
storefront is shown the English listing and, once installed, an app that speaks
Bengali. Spanish is the mirror image: one translation, two storefront locales —
`es-MX` exists because a listing that stops at `es-ES` leaves Latin America
reading English.
