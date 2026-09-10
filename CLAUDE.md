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

## The repository is public: nothing private goes into it

Everything committed here is published, permanently, under the author's name. A
value that lands is in the history from that moment — fixing it forward does not
remove it, and the history has already been rewritten twice to take one out.
Treat this as the rule that outranks convenience: an agent working here checks
what it is about to write, every time, and does not assume a value is harmless
because it is only a comment, only a test fixture, or only an example.

**What must never appear:** a home directory or any absolute path from one
machine; the name or login of the machine this is written on; a mail address
outside the reserved example domains; an account identifier taken from a running
instance; anything shaped like a credential — a key prefix, a JSON web token, a
value beside the word token, secret, password or key; a routable host address;
the Apple team identifier; a bundle identifier belonging to another project; a
path into a neighbouring checkout. Commit messages count as part of the
repository — a value written into one is in no file a scan of the tree walks.

**The guard.** `NoPersonalDataInTheRepository` holds all of this, and
`tools/install-hooks.sh` points git at a pre-commit hook that runs it. Install it
once per clone. The guard is a floor, not a ceiling: it catches the shapes it
knows about, and something private in a shape nobody has met yet will pass it.

**Writing a fixture that needs a forbidden shape.** Assemble it at runtime rather
than writing it out — `"/Users/" + "someone"`, `"sk-ant-" + "…"`. The test that
proves home paths are scrubbed cannot itself contain one, and that is the rule
working rather than the rule getting in the way. `ScrubberTests` does this and
says why.

**Reaching outside the repository.** Infrastructure this project shares with the
author's other work is reached by names of its own — `sentry.softcap.app`, not
the host the same server answers to elsewhere. A hostname committed here is
published with the repository, and the association is the private part.
