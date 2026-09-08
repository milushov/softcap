#!/bin/bash
#
# Signs a built .app, nested code first.
#
#     tools/sign_app.sh <path-to-.app>
#
# Reads two optional variables:
#
#     SIGN_IDENTITY   codesign identity; "-" (ad-hoc) when unset
#     TEAM_ID         Apple team identifier, when signing with a real
#                     Developer ID certificate
#
# Why the app is signed here rather than by xcodebuild: the entitlements ask for
# an app group, and with CODE_SIGN_STYLE=Manual Xcode refuses to sign that
# without a provisioning profile — which a runner with no Apple account cannot
# get. Building unsigned and signing afterwards applies the same entitlements
# with an ad-hoc signature and no profile.
#
# The group is what lets the widget read what the app fetched, so dropping the
# entitlement to make the build pass would ship an app whose widget is
# permanently blank.

set -euo pipefail

APP=${1:?usage: sign_app.sh <app>}
IDENTITY=${SIGN_IDENTITY:--}
TEAM=${TEAM_ID:-}

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT

# `$(TeamIdentifierPrefix)` is a build setting, so it survives verbatim into the
# entitlements file. Xcode expands it while signing; doing it by hand here.
# Ad-hoc signatures have no team, and the prefix then has to go entirely — an
# app group beginning with a dot is not a valid group name.
prepare() {
    local src=$1 out=$2
    if [ -n "$TEAM" ]; then
        sed "s/\\\$(TeamIdentifierPrefix)/${TEAM}./g" "$src" > "$out"
    else
        sed 's/\$(TeamIdentifierPrefix)//g' "$src" > "$out"
    fi
}

prepare "$ROOT/App/Softcap.entitlements"          "$WORK/app.entitlements"
prepare "$ROOT/Widget/SoftcapWidget.entitlements" "$WORK/widget.entitlements"

# A secure timestamp is what lets a signature keep verifying after the
# certificate behind it expires, and notarisation rejects a build without one.
# It is fetched from Apple's server, which an ad-hoc signature has no reason to
# contact — and no certificate to stamp.
TIMESTAMP=(--timestamp)
[ "$IDENTITY" = "-" ] && TIMESTAMP=(--timestamp=none)

# Nested code before the bundle that contains it: signing the outer bundle seals
# a hash of the inner one, so signing them the other way round invalidates the
# outer signature immediately. (`--deep` would do this, but Apple deprecated it
# and it applies the wrong entitlements to the extension.)
APPEX="$APP/Contents/PlugIns/SoftcapWidget.appex"
if [ -d "$APPEX" ]; then
    codesign --force "${TIMESTAMP[@]}" --options runtime \
        --sign "$IDENTITY" --entitlements "$WORK/widget.entitlements" "$APPEX"
fi

codesign --force "${TIMESTAMP[@]}" --options runtime \
    --sign "$IDENTITY" --entitlements "$WORK/app.entitlements" "$APP"

codesign --verify --deep --strict "$APP"
codesign -dv "$APP" 2>&1 | grep -E 'Signature|TeamIdentifier' || true
