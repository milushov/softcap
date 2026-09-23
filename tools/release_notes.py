#!/usr/bin/env python3
"""What changed in the app since the previous release, read from git.

    python3 tools/release_notes.py changed
        `true` when a commit since the previous release touched something the
        disk image is made of, `false` otherwise. The release workflow builds
        nothing when this says false — unless it was started by hand.

    python3 tools/release_notes.py notes [--tag v0.1.37] [--repository owner/name]
        The top of the release body: one line per such commit, oldest first,
        then the line naming the commit and the day — with a link to everything
        since the previous release when the tag and the repository are given.

The previous release is the nearest tag shaped like a version that HEAD
descends from. A shallow checkout — what `actions/checkout` makes unless told
otherwise — holds no tag, and in one this would answer "no previous release":
nothing listed, everything built, and no step failing to say so. So a shallow
checkout is refused, with the checkout option it needs in the message.

No third-party modules, and nothing newer than Python 3.9: the runner's own
python3 is what runs this, in the job that decides whether anything else runs.
"""

import argparse
import datetime
import re
import subprocess
import sys

# What the disk image is made of: the sources, the assets, the project that
# builds them, and the pipeline that signs and packages the result — a change
# to signing is a change the person downloading meets. A commit that touched
# none of these did not change the build, however its subject reads: the one
# that let the staleness badge shrink touched the landing page's mock and
# nothing else, and the release it triggered was the same app again.
#
# `:(top)` makes each path relative to the repository's root rather than to
# wherever the tool was run from.
THE_APP = [
    "App",
    "Packages",
    "Widget",
    "Resources",
    "project.yml",
    "Signing.xcconfig",
    ".github/workflows/release.yml",
    "tools/sign_app.sh",
    "tools/make_dmg.sh",
]

# Inside one of those paths and not in the macOS build. `Resources/` holds the
# phone's asset catalogue beside the Mac's, and a redrawn iOS icon would
# otherwise publish a disk image identical to the last one — the harm the gate
# exists to prevent, inverted. The same hole remains inside `project.yml`, which
# declares the two iOS targets in the same file as the Mac ones: a pathspec
# cannot see half a file, and splitting the project definition to close it would
# cost more than the occasional wasted build.
NOT_THE_APP = [
    "Packages/Core/Tests",
    "Resources/iOSAssets.xcassets",
]

# GitHub's five spellings of "run no workflow for this commit" — an instruction
# to CI, not part of the change, and not for the reader.
#
# Unanchored, because GitHub honours the marker anywhere in the subject and this
# repository's own habit of putting it last is a habit rather than a rule. Left
# anchored to the end, `[skip ci] Re-sign with the new Developer ID` reached the
# release page and the app's Updates box with the brackets still on, where the
# markdown reader renders them as the wreckage of a link.
SKIP_CI = re.compile(
    r"\s*\[(?:skip ci|ci skip|no ci|skip actions|actions skip)\]\s*", re.IGNORECASE
)

RELEASE_TAG = "v[0-9]*"


def fail(message):
    """Say what is wrong in one line, and stop. Exit 2, as the shallow refusal
    does: the workflow treats it as "this question could not be answered"."""
    print("release-notes: " + message, file=sys.stderr)
    sys.exit(2)


def git(*arguments):
    """What git printed, stripped. Raises when git refuses."""
    return subprocess.run(
        ["git", *arguments], check=True, capture_output=True, text=True
    ).stdout.strip()


def pathspecs():
    """The app, as git pathspecs. `:(top)` makes each one relative to the
    repository's root rather than to wherever the tool was run from."""
    return ([":(top)" + path for path in THE_APP]
            + [":(top,exclude)" + path for path in NOT_THE_APP])


def refuse_a_shallow_checkout():
    if git("rev-parse", "--is-shallow-repository") == "true":
        print(
            "release-notes: this checkout is shallow, so the previous release's tag "
            "is out of reach and every commit would read as new. Check out the "
            "history: actions/checkout with `fetch-depth: 0`.",
            file=sys.stderr,
        )
        sys.exit(2)


def previous_release():
    """The nearest version tag HEAD descends from, or None before the first.

    A failure to describe is not the same answer as "there has been no release",
    and treating it as one walks into the fault the shallow refusal above exists
    to prevent, by another door: after a history rewrite — which this repository
    has done twice — the tags survive without being ancestors of anything, git
    answers "No tags can describe", and every release would quietly go back to
    listing nothing. So the two are told apart by asking whether any release tag
    exists at all.
    """
    try:
        return git("describe", "--tags", "--abbrev=0", "--match", RELEASE_TAG, "HEAD")
    except subprocess.CalledProcessError:
        pass
    if git("tag", "--list", RELEASE_TAG):
        fail("there are release tags, and none of them describes HEAD — the history "
             "was rewritten, or this branch grew from somewhere else. Nothing can be "
             "said about what changed since the last release until that is sorted out.")
    return None


def version_of(tag):
    """`v0.1.36` is the tag; `0.1.36` is what the release is called."""
    return tag[1:]


def changes_since(tag):
    """The subjects of the commits since `tag` that touched the app, oldest first.

    `--no-merges`, because "Merge remote-tracking branch 'origin/main'" tells a
    reader nothing and the commits it brought in are in the range anyway. That
    is also what makes this the wrong question to gate a build on — see
    `app_changed_since`.

    Emptiness is judged after the instruction to CI is trimmed, not before: a
    commit whose whole subject is `[skip ci]` is a line in the log and nothing
    at all to a reader, and judged before it would have been published as a
    bullet with no words after it.
    """
    log = git("log", "--no-merges", "--reverse", "--format=%s", tag + "..HEAD", "--",
              *pathspecs())
    subjects = (SKIP_CI.sub(" ", line).strip() for line in log.splitlines())
    return [subject for subject in subjects if subject]


def app_changed_since(tag):
    """Whether the tree differs from `tag` in anything the image is made of.

    Two trees compared, not a list of commits counted, because the list leaves
    merge commits out and a merge commit can carry a change of its own: a
    conflict resolved by hand belongs to the merge and to nothing else. This
    repository makes that shape routinely — CI pushes a README commit, the
    author pulls — and a gate reading the list would have skipped such a
    release with every step green.
    """
    answer = subprocess.run(["git", "diff", "--quiet", tag, "HEAD", "--", *pathspecs()],
                            capture_output=True, text=True)
    if answer.returncode in (0, 1):
        return answer.returncode == 1
    fail("git could not compare this checkout with %s: %s"
         % (tag, answer.stderr.strip() or "no reason given"))


def changed():
    previous = previous_release()
    print("true" if previous is None or app_changed_since(previous) else "false")


def notes(tag, repository):
    """The top of the release body, written for two readers at once.

    GitHub renders it under the version; the app's Updates screen shows the
    same text in a box a few lines tall, interpreting inline Markdown only —
    so the list is first, and there is no heading over it to print literally.
    """
    previous = previous_release()
    changes = changes_since(previous) if previous is not None else []
    lines = []
    if changes:
        lines.extend("- " + subject for subject in changes)
        lines.append("")
    elif previous is not None and not app_changed_since(previous):
        lines.append("Nothing in the app changed since %s — the same sources, built again."
                     % version_of(previous))
        lines.append("")
    # The third case says nothing at all: the tree differs and no ordinary
    # commit accounts for it, which is a merge carrying its own change. Better
    # a body that opens with the commit it was built from than one asserting
    # that nothing changed while the build proves otherwise.

    # UTC, which is also what the workflow dates the README's download line in:
    # a release is dated when it was published, not where the author was
    # standing (DECISIONS, 2026-09-14).
    today = datetime.datetime.now(datetime.timezone.utc).date().isoformat()
    built = "Built from `%s` on %s." % (git("rev-parse", "--short=7", "HEAD"), today)
    # Its own sentence rather than a clause hanging off that one, because the
    # app's Updates box strips the link and keeps the words: "— everything since
    # 0.1.36." dangles there, where "Everything since 0.1.36." reads.
    #
    # Not on the rebuild branch: a line offering everything since 0.1.36 under a
    # sentence saying nothing since 0.1.36 changed is two answers to one
    # question, and when HEAD is the tagged commit it links an empty comparison.
    if changes and tag and repository:
        built += " [Everything since %s](https://github.com/%s/compare/%s...%s)." % (
            version_of(previous), repository, previous, tag
        )
    lines.append(built)
    print("\n".join(lines))


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("changed", help="true or false: did anything in the app change")
    notes_parser = commands.add_parser("notes", help="the top of the release body")
    notes_parser.add_argument("--tag", help="the tag this release will carry, e.g. v0.1.37")
    notes_parser.add_argument("--repository", help="owner/name on GitHub, for the compare link")
    args = parser.parse_args(argv)

    # Every git failure that is not one of the answers above arrives here, and
    # arrives as a sentence: run outside a repository, this printed a traceback
    # with git's own "not a git repository" swallowed inside it.
    try:
        refuse_a_shallow_checkout()
        if args.command == "changed":
            changed()
        else:
            notes(args.tag, args.repository)
    except subprocess.CalledProcessError as refusal:
        fail("git refused `%s`: %s" % (" ".join(refusal.cmd[1:]),
                                       (refusal.stderr or "").strip() or "no reason given"))
    except FileNotFoundError:
        fail("git is not on the PATH, so nothing here can be answered.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
