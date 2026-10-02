# Softcap — project rules

## Which branch to work in

**This repository has no `staging`, so the working branch is `main`.** Across
these projects the rule is: work in `staging`; where there is no `staging`,
work in `main`.

**Work in the local `main`, not `origin/main`.** The source of truth is the
branch on disk: it can be a dozen commits ahead of the remote — or a hundred —
and that is a normal state, not a desync to be repaired. It follows that:

- read the state of the work with `git log main`, not `git log origin/main`,
  and do not treat unpushed commits as lost;
- never reset or fast-forward onto `origin/main` — that destroys hours of work;
- `git pull --rebase` before pushing if the remote has moved ahead, but never
  `git reset --hard origin/main`;
- pushing is a separate human decision: it is also a deploy, and it publishes
  the commits of parallel sessions sitting in the same branch.

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

## History stays flat

**The working branch carries no merge commits.** A branch lands by
fast-forward, which means it is rebased onto the current tip first and never
merged into it:

```bash
git config rerere.enabled true    # once per clone: remembers a resolution
git rebase main <branch>
git switch main && git merge --ff-only <branch>
```

A refused `--ff-only` means the branch is behind, not that a merge is wanted —
rebase it again. `rerere` is not decoration: rebasing a long branch raises the
same conflict once per commit that touches the file, and with it enabled the
resolution is given once.

**Flat means linear, not collapsed.** A branch arrives as its own commits:
each one is a reviewable unit, and the sequence is the record of how the work
was built. Squashing a branch into a single commit destroys that record.

**Verifying is part of the rule, not an afterthought.** A merge node appears
without being asked for — a plain `git pull` against a remote that has moved
produces one — and once it is pushed it cannot be removed without rewriting
history that other sessions and the remote already hold. The only moment it is
fixable is before the push:

```bash
make history-check   # fails if a merge commit is waiting to be pushed
```

Run it before every push. Note that this machine sets `merge.ff = false`
globally, so a bare `git merge` writes a merge node even where a fast-forward
was possible — pass `--ff-only` every time and let it refuse. If the check
reports a node that is already published, say so and stop: rewriting shared
history is a decision for a human, not a cleanup to perform quietly.


## Committing is part of the work, not the end of it

**Commit each piece as it lands.** Finished a task — commit it, without waiting
for the end of the session and without asking. Only pushing needs a human.

A tree that accumulates modified files is not tidiness, it is a liability, and
here it is a shared one. An uncommitted edit lives exactly until another
session's broad `git add` or `git checkout`, after which it leaves inside
someone else's commit under someone else's message, or disappears without
trace. And work that is not in `git log` does not exist for anyone else: there
is no review of it, no rebase onto it, and no way back to it.

**Commit by pathspec, not merely add by pathspec.** `git commit` commits the
whole index, so whatever a concurrent session staged before you started travels
with your change. Measured here: an explicit `git add` of two files followed by
a plain `git commit` produced a commit carrying four of another session's staged
files.

```bash
git commit -m "..." -- path/one path/two
```

That form commits only the named paths and leaves everything else staged, so a
peer's in-flight work is preserved exactly as it was. Audit afterwards with
`git show --name-only --format='' HEAD` and expect only your own files.

**Pathspec and partial staging are mutually exclusive.** `git commit -- <paths>`
takes the *working tree* content of those paths and disregards the index for
them. So staging one hunk and then committing with a pathspec commits the whole
file, the peer's hunk included — measured on 2026-10-02, the hard way, after
the hunk had been isolated correctly and the pathspec threw that work away.

When the peer's edits are in **other files**, use the pathspec form: it leaves
those files staged and untouched. When they are in **the same file as yours**,
stage only your hunks and commit with **no pathspec**, which commits the index
exactly:

```bash
git apply --cached my-hunk.patch
git diff --cached              # must show only your own changes
git commit -m "..."            # no pathspec, so the index is what lands
```

Check which case you are in before choosing, because the wrong one fails
silently: the commit succeeds and simply contains more than you meant.

Leave the tree clean behind you — when a task is done, `git status --porcelain`
shows nothing of yours.

## Independent pieces: `/orchestrated-development`

When a task genuinely splits into pieces that can be built without shared state
— several independent fixes, a feature across disjoint files, plan tasks that do
not depend on each other — that skill runs them in one session rather than one
at a time: one agent per independent domain, each in its own worktree, each with
its own implement → review → fix loop.

It carries the rules above rather than fighting them: branches land by rebase
and `git merge --ff-only`, each node's worktree and branch are destroyed when it
finishes, commits go in by pathspec, and pushing is left to a human.

Only for genuinely independent pieces. Dependent work stays sequential and a
single-file change stays a single edit — the width is a readout of the
decomposition, never a habit.
