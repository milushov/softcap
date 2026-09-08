# Work plans

Three plans, thirty-one tasks. Nearly all of it was built, and the reasoning is
sometimes the only record of why a thing was made the way it was — which is why
they are kept. They are not a to-do list, and they are **not** a reliable record
of what was finished. Two things they specify were found missing from the code
long afterwards: the shortcut that opens the window, which had a settings field
and an identifier and nothing that registered it, and the tests for the menu
bar's countdown. Both are in the decision log.

**Everything else has since been checked.** Every file path the three plans name
exists or has a recorded rename; of three hundred and sixteen types, functions
and test names they specify, fifteen are absent and every one of them is a
rename, a move, or a design that changed on purpose — `ThresholdNotifier` became
`ThresholdTracker`, the row moved into `StatusUI`, `formatRemainingCompact`
became `remainingCompact`, `Scope` became `WindowScope`, and `unregisterAll` was
never needed because `register` unregisters the same identifier first. So the
plans are an unreliable record of what was *finished*, and a complete one of what
was *specified*: nothing in them was quietly dropped.

| Plan | Tasks | What it built |
|---|---|---|
| `2026-08-30-macos-menu-bar-prototype.md` | 12 | The first working app: providers, the poller, the menu bar item and the window. |
| `2026-08-30-settings-screen.md` | 13 | The settings window and every pane in it. |
| `2026-08-31-rename-to-softcap.md` | 6 | StatusChecker to Softcap, across four bundle identifiers, the app group and the widget kinds. |

**They open with a banner addressed to a tool**, not to you:
*"REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development…"*. That is how
they were executed. Skip it.

**Two of them have Russian in places.** The first two were written when the
project's working language was Russian; the third is entirely English, as
everything since has been.

**The checkboxes were never used.** There are 214 of them and not one is ticked.
An earlier version of this note said the opposite — that they were the plan's own
progress tracking and all of it was ticked — which was written without counting
them. To know whether something in a plan was built, look for it in the code.

## Where the current record is

A plan says what was going to be done. `docs/DECISIONS.md` says what was done,
why, and at what it cost — including the parts that turned out differently from
the plan, and the mistakes. It is the file to read; these are the file to consult
when the log refers to something and you want the shape of the original work.

`docs/superpowers/specs/` holds the design documents the plans were written from.
They are marked approved and implemented, and their "out of scope" sections date
from before the iOS app, the widgets and the statistics screen existed.
