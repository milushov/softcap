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

# Under Packages, and not in the build.
NOT_THE_APP = [
    "Packages/Core/Tests",
]

# GitHub's five spellings of "run no workflow for this commit" — an instruction
# to CI, not part of the change, and not for the reader.
SKIP_CI = re.compile(
    r"\s*\[(?:skip ci|ci skip|no ci|skip actions|actions skip)\]\s*$", re.IGNORECASE
)

RELEASE_TAG = "v[0-9]*"


def git(*arguments):
    """What git printed, stripped. Raises when git refuses."""
    return subprocess.run(
        ["git", *arguments], check=True, capture_output=True, text=True
    ).stdout.strip()


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
    """The nearest version tag HEAD descends from, or None before the first."""
    try:
        return git("describe", "--tags", "--abbrev=0", "--match", RELEASE_TAG, "HEAD")
    except subprocess.CalledProcessError:
        return None


def version_of(tag):
    """`v0.1.36` is the tag; `0.1.36` is what the release is called."""
    return tag[1:]


def changes_since(tag):
    """The subjects of the commits since `tag` that touched the app, oldest first."""
    log = git(
        "log", "--no-merges", "--reverse", "--format=%s", tag + "..HEAD", "--",
        *(":(top)" + path for path in THE_APP),
        *(":(top,exclude)" + path for path in NOT_THE_APP),
    )
    return [SKIP_CI.sub("", line) for line in log.splitlines() if line.strip()]


def changed():
    previous = previous_release()
    print("true" if previous is None or changes_since(previous) else "false")


def notes(tag, repository):
    """The top of the release body, written for two readers at once.

    GitHub renders it under the version; the app's Updates screen shows the
    same text in a box a few lines tall, interpreting inline Markdown only —
    so the list is first, and there is no heading over it to print literally.
    """
    previous = previous_release()
    lines = []
    if previous is not None:
        changes = changes_since(previous)
        if changes:
            lines.extend("- " + subject for subject in changes)
        else:
            lines.append(
                "Nothing in the app changed since %s — the same sources, built again."
                % version_of(previous)
            )
        lines.append("")

    # UTC, as the README's download line is: a release is dated when it was
    # published, not where the author was standing (DECISIONS, 2026-09-14).
    today = datetime.datetime.now(datetime.timezone.utc).date().isoformat()
    built = "Built from `%s` on %s" % (git("rev-parse", "--short=7", "HEAD"), today)
    if previous is not None and tag and repository:
        built += " — [everything since %s](https://github.com/%s/compare/%s...%s)" % (
            version_of(previous), repository, previous, tag
        )
    lines.append(built + ".")
    print("\n".join(lines))


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("changed", help="true or false: did anything in the app change")
    notes_parser = commands.add_parser("notes", help="the top of the release body")
    notes_parser.add_argument("--tag", help="the tag this release will carry, e.g. v0.1.37")
    notes_parser.add_argument("--repository", help="owner/name on GitHub, for the compare link")
    args = parser.parse_args(argv)

    refuse_a_shallow_checkout()
    if args.command == "changed":
        changed()
    else:
        notes(args.tag, args.repository)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
