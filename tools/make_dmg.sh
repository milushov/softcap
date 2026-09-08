#!/bin/bash
#
# Packs a built .app into a drag-to-Applications disk image.
#
#     tools/make_dmg.sh <path-to-.app> <version> <output-dir>
#
# Deliberately built on `hdiutil` alone rather than `create-dmg`: the nicer
# window layout that tool produces is set through AppleScript, which needs a
# Finder that a headless CI runner does not have. A staging folder with the app
# and a symlink to /Applications gives the same drag-and-drop gesture with
# nothing to go wrong.

set -euo pipefail

APP=${1:?usage: make_dmg.sh <app> <version> <outdir>}
VERSION=${2:?usage: make_dmg.sh <app> <version> <outdir>}
OUTDIR=${3:?usage: make_dmg.sh <app> <version> <outdir>}

NAME=$(basename "$APP" .app)
STAGE=$(mktemp -d)
# `${STAGE:?}` rather than "$STAGE": an unset variable here would otherwise
# expand to a delete of the filesystem root.
trap 'rm -rf "${STAGE:?}"' EXIT

mkdir -p "$OUTDIR"
DMG="$OUTDIR/$NAME-$VERSION.dmg"
rm -f "$DMG"

# The volume the user sees mounted. Keep the version out of it: the window
# title is a place to recognise the app, not to read a build number.
VOLNAME="$NAME"

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# UDZO is the compressed read-only format every macOS since 10.x mounts without
# a prompt. `-quiet` keeps the CI log readable; failures still raise an exit code.
hdiutil create \
    -volname "$VOLNAME" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    -quiet \
    "$DMG"

echo "$DMG"
