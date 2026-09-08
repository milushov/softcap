#!/usr/bin/env bash
#
# Points git at the hooks kept in this repository.
#
# `.git/hooks` is not tracked, so a hook committed to the project reaches nobody
# until git is told where to look. `core.hooksPath` is that instruction, and it
# is per-clone — hence a script rather than a note somebody has to follow.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
git -C "$root" config core.hooksPath tools/hooks
echo "hooks: $(git -C "$root" config core.hooksPath)"
