# The window offers the way back in

An account list this build cannot open is a state with a way out, and until now
the way out was on a screen nobody in that state goes looking for. This puts it
in the window that states the problem.

## The situation

Somebody updates Softcap, clicks the menu bar icon, and reads:

> **No accounts found**
> Add an account in Settings — Softcap opens your browser to sign in.

Their accounts are not gone. The keychain binds item access to the signature
that wrote it, and a build signed differently is a different application to the
keychain — so an update is enough to produce this. The refresh tokens are intact
and one question away. The sentence on screen says otherwise, and the advice
under it — sign in again — spends a grant to fix something that is not broken.

The machinery to tell the difference already exists and predates this work:

| what the keychain answered at launch | `CredentialStore.whyUnreadable()` |
|---|---|
| `errSecItemNotFound` | `nil` — nothing was ever saved |
| `errSecAuthFailed`, `errSecInteractionNotAllowed` | `.keychainRefusedThisBuild` |
| locked, missing, broken | `.keychainDidNotOpen` |
| opened, and undecodable | `.contentNotUnderstood` |

`CredentialStore.load()` makes that read once, at launch, with user interaction
turned off — so the answer is on hand before anybody clicks anything, and no
dialog was raised to get it. `AppModel.accountsProblem()` already hands it to
the Accounts screen, which shows a repair block with **Open saved accounts** and
**Start over…**.

What is missing is a single edge: the window does not ask. `PopoverView.empty`
branches on `lastUpdated` alone, so both windows state the fresh-install
conclusion over a keychain that refused them.

## What changes

### The window says which kind of empty it is

`PopoverView.empty` gains two branches. The order is fixed and is the point:

1. `model.lastUpdated == nil` — still looking. Unchanged, and still first: a
   conclusion drawn before the first poll returns is how the app was mistaken
   for a broken one.
2. `.keychainRefusedThisBuild` or `.keychainDidNotOpen` — a lock symbol, the
   heading **Your accounts are still here**, the reason, an **Open saved
   accounts** button and a quiet **Settings…** beneath it.
3. `.contentNotUnderstood` — a warning symbol, the heading **Saved accounts
   could not be opened**, the reason, and **Settings…** alone.
4. Otherwise — **No accounts found**, as today.

Both shapes of the window get it: `empty` is drawn by `full` and by `minimal`
alike, and the minimal window is where somebody who has taken everything off the
screen will meet this.

Three and four are separated deliberately. In three, the item opened and what
came out makes no sense to this build; the only way on deletes every refresh
token in it. "Your accounts are still here" would be a promise the app cannot
keep, and **Start over…** is a button that destroys credentials — it stays on
the screen that asks about it first, not in a window a stray click can reach.

### The window knows without asking the keychain

`AppModel` publishes `savedAccountsProblem: UnreadableAccountList?`, set at the
end of each poll from the existing `accountsProblem()`. No new keychain read:
`load()` asked once at launch and the actor has been holding the answer since.

This is also the whole of "know in advance whether there are any". A fresh
install answers `errSecItemNotFound`, `unreadable` stays `nil`, and branches two
and three cannot be reached. Nobody is shown a repair for accounts they never
had.

`AccountsPane` drops its `@State private var problem` and reads the published
property. It reloaded that state from three separate `onChange` hooks, and two
screens reading one fact from two places is two screens that can disagree about
it.

### The press keeps the window open

The keychain's question is a system dialog, and a `.transient` popover closes
itself the moment focus leaves. Pressed as-is, the window vanishes and a
password prompt appears with nothing left on screen to explain it.

`AppModel` gains a `keychainDialogRequests` counter, the shape
`appearancePreviewRequests` already uses. `StatusItemController` observes it and
holds `popover.behavior = .applicationDefined` while it is above zero, restoring
`.transient` after.

A press therefore: raises the counter, activates the app so the dialog comes out
in front, replaces the button with a spinner, calls
`AppModel.openSavedAccounts()`, refreshes, and lowers the counter. The read
waits off the store's actor, so the app stays alive for as long as the dialog
stands open — that is `openWithPermission()`'s existing design and the reason it
was written that way.

A refusal costs nothing. The list stays shut, the write guard stays up, the
button can be pressed again, and the keychain's status goes to the log.

### One new sentence

`"Your accounts are still here"`, in ten catalogues via `tools/add_strings.py`.

Everything else on the new screens is already translated: `Open saved accounts`,
`Settings…`, `Saved accounts could not be opened`, and all three explanations.
The refusal reuses the Accounts screen's own sentence — *"This copy of the app
is not the one that saved them. The keychain will ask once — choose 'Always
Allow'."* It runs longer in a 322-point window than a line written for the
window would, and it says why as well as what, at a cost of zero translations.
Somebody who has seen one screen should not have to work out that the other
means the same thing.

`explanation(of:)` leaves `AccountsPane` for `App/SavedAccountsProblem.swift`,
which answers four questions about a reason: heading, explanation, symbol, and
whether opening can be offered at all. Both screens read it.

Not `StatusUI`, where the catalogues live: that target does not depend on
`Credentials` and must not start — it is what the widgets are built from, and
the credential store has no business in a widget. The App target already imports
both, and assembling labels from the catalogues is what the UI layer is for.

## What this does not fix

A move between distribution channels. The App Store build is sandboxed into a
keychain access group of its own, so the item the GitHub build wrote is not
refused — it is not found. From inside, that is a fresh install, and the window
will say **No accounts found**. It will be telling the truth about the keychain
it can see.

## Tests

- `TheWindowSaysItIsStillLooking` holds `lastUpdated == nil` first among the
  branches. Extended so the new branches cannot overtake it.
- A new suite scans `PopoverView` for the rest: the window asks about the
  problem before concluding `No accounts found`; `contentNotUnderstood` reaches
  no repair button; the window's button calls the same `openSavedAccounts()` the
  settings screen calls, rather than a second path to the keychain.
- `NoOrphanStrings` and `LocalizationTests` take the new key without being told.

Source scans rather than rendered views, as the existing suites do: a popover
cannot be instantiated in a test process, and what these hold is the shape of
the decision, which reads perfectly well in the source.

## Cost

One sentence in ten languages. A published property and a counter on `AppModel`,
and a Combine subscription in `StatusItemController` that can pin the window —
which means a bug there can leave a popover that will not close by itself, so it
is restored in `defer` and not on the success path.

A window that used to have one empty state now has four, and every future change
to it has to keep four straight.
