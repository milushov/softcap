# What to tell App Review about updates

App Review refused 0.1.36 on 24 September 2026 under guideline 2.4.5(vii),
*"The app updates itself outside of the Mac App Store"*. The refusal was
correct: for four days the store build checked the App Store's own lookup
record once a day and said in the menu and on an Updates screen that a newer
version was on sale. It installed nothing, and that is not the line the
guideline draws — it forbids the additional check as well as the install.

The build that goes back has no updater at all. `docs/DECISIONS.md`,
2026-09-25, holds the whole of the reasoning; this file holds the text.

Nothing needs to be argued in Resolution Center. A reply is only worth sending
if the resubmission is refused again for the same guideline, and in that case
the paragraph below is the answer, because it names what a reviewer can check.

---

## For App Store Connect → the version → App Review Information → Notes

Paste this under the existing paragraph about the network entitlement. It goes
on every submission: the notes belong to one version, and a new version starts
without them.

> Updates: this build performs no update check of any kind. Guideline
> 2.4.5(vii) — Settings has no Updates section, the menu bar menu has no update
> item, the settings footer prints the version and offers nothing, and nothing
> is requested from any host about versions. It is compiled out rather than
> switched off (`#if !APPSTORE`): no code path in this build can reach an update
> check, and the App Store's lookup record is not read anywhere. The copy
> distributed outside the App Store, as a disk image from the project's own
> releases page, keeps that feature; the two are built from one source with
> different compilation conditions, and only the disk image carries it.

And, for the guideline 5 item in the same letter:

> China, from the guideline 5 rejection: this app is no longer distributed in
> mainland China. The China storefront was deselected in Availability on
> 25 September 2026, which is the alternative the rejection offers to changing
> the functionality and the metadata for that storefront.

**Do not claim the binary names no update host.** It does: `Updates` is linked
into the store build for `ReleaseVersion`, which the settings footer needs to
print the version, and the module carries `ReleaseFeed.latestURL` —
`api.github.com/repos/…/releases/latest` survives in `__TEXT` with nothing
calling it. Removing it means splitting `ReleaseVersion` into a module of its
own. Every build App Review has approved, 0.1.25 included, carried the same
string, so it has never been the thing that was read. A claim a `strings` dump
contradicts is worse than no claim.

## What a reviewer sees

- The menu bar menu, top to bottom: `Softcap <version>` as its heading,
  Refresh, Settings…, Add account, Statistics, Minimal window, Quit Softcap.
  The heading prints the version this copy is; it asks nothing and is not a
  control. There is no "Check for updates…" and no "Update to …".
- Settings: eight sections — Accounts, Statistics, Appearance, Notifications,
  Polling and launch, Services, Contribute, About and data. No Updates.
- The settings footer: the version number alone, with nothing to press.

## What holds it

`TheStoreCopyHasNoUpdater` reads the sources on every test run: the daily check
guarded by `#if !APPSTORE`, the Updates section filtered out of the store
build, the menu item and footer button guarded, `UpdateModel` with no App Store
channel and no reader for the store's record, and no Swift file in the project
naming `itunes.apple.com`. `NothingElseLeavesYourMac` holds the host list the
privacy page is written from, and both Apple hosts are gone from it.
