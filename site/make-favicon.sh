#!/usr/bin/env bash
#
# Rebuilds favicon.ico from icon.svg.
#
# Three sizes in one file. Below 40 px the inner ring is dropped and the outer one
# thickened — the app's icon generator does the same, for the same reason: two
# concentric strokes a few pixels apart merge into a smudge rather than reading as
# two rings. This is the same mark, so it follows the same rule.
#
#   ./make-favicon.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
[ -x "$CHROME" ] || { echo "Chrome not found; set CHROME" >&2; exit 1; }

python3 - "$HERE" <<'PY'
import pathlib, sys
here = pathlib.Path(sys.argv[1])
svg = (here / "icon.svg").read_text()
small = []
for line in svg.splitlines():
    if 'r="11.5"' in line:
        continue
    if 'r="21"' in line:
        line = line.replace('stroke-width="5"', 'stroke-width="7"')
    small.append(line)
pathlib.Path("/tmp/icon_small.svg").write_text("\n".join(small))
PY

for S in 16 32 48; do
  SRC="$HERE/icon.svg"; [ "$S" -lt 40 ] && SRC=/tmp/icon_small.svg
  {
    printf '<!doctype html><html><head><meta charset="utf-8"><style>\n'
    printf 'html,body{margin:0;padding:0;width:%spx;height:%spx;overflow:hidden}\n' "$S" "$S"
    printf 'svg{display:block;width:%spx;height:%spx}\n</style></head><body>\n' "$S" "$S"
    cat "$SRC"
    printf '\n</body></html>\n'
  } > "/tmp/fav_$S.html"
  # A transparent page behind the mark, so the corners outside its rounded square
  # stay clear. Without this Chrome paints the page white and the icon arrives as
  # a white square with rounded dark inside it — which is invisible on a light tab
  # bar and glaring on a dark one.
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size="$S,$S" \
    --default-background-color=00000000 \
    --virtual-time-budget=2000 --screenshot="/tmp/fav_$S.png" "file:///tmp/fav_$S.html" >/dev/null 2>&1
done

python3 - "$HERE" <<'PY'
import struct, pathlib, sys
here = pathlib.Path(sys.argv[1])
sizes = [16, 32, 48]
images = [pathlib.Path(f"/tmp/fav_{s}.png").read_bytes() for s in sizes]
header = struct.pack("<HHH", 0, 1, len(images))
offset = 6 + 16 * len(images)
entries, blobs = b"", b""
for size, data in zip(sizes, images):
    entries += struct.pack("<BBBBHHII", size, size, 0, 0, 1, 32, len(data), offset)
    blobs += data
    offset += len(data)
(here / "favicon.ico").write_bytes(header + entries + blobs)
print(f"favicon.ico rebuilt: {len(header+entries+blobs)} bytes, {len(images)} sizes")
PY
