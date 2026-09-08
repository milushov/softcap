# Softcap — project rules

## Documentation language: English

All documentation in this repository is written in **English** — README, the
decision log, specs, plans, and code comments. Conversation with the author stays in
Russian.

The project ships a ten-language interface; its own documents should not be
locked to one language. When editing an existing document, translate it rather
than appending English to Russian text — a mixed-language file is worse than
either language alone.

## Architecture rule: no human-facing strings in Core

`Packages/Core` returns identifiers and numbers, never text shown to a person.
Labels are assembled by the UI layer from the catalogues in `StatusUI`.

This is enforced by a test that scans the sources (`CoreHasNoHumanStrings`).
The one exception is `ProviderID.title` — `Claude` and `Codex` are brand names
and are not translated.

Adding a string to the UI means adding it to all ten catalogues. Use
`tools/add_strings.py`; a test checks that key sets and placeholders match.

## Decisions are logged

Every non-obvious decision goes into `docs/DECISIONS.md` with three parts: what
was decided, why, and what it cost. Entries are never rewritten — a reversed
decision gets a new entry referring to the old one.
