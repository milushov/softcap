#!/usr/bin/env python3
"""Cuts the app window out of each App Store screenshot.

    python3 tools/crop_screenshots.py [out-dir]     writes PNGs; run cwebp after

The five shots in `docs/screenshots` are marketing images: a saturated gradient,
a baked-in English caption, and the window in the lower two thirds. Neither the
gradient nor the caption belongs on a site that ships ten languages and two
palettes, so only the window is kept — the caption becomes translated text in
the page and the shadow becomes CSS that can differ between light and dark.

Four of the five are found by saturation: the window chrome is neutral and every
pixel of the gradient behind it, shadow included, is a saturated blue or teal.
`05-minimal` is the exception and is measured rather than found — its window is
a vibrancy material that takes the wallpaper's own blue, so it is no more
neutral than the background it sits on. Its edges were read off a luminance scan
instead: a bright one-pixel border at x 392 and 1046, y 314 and 699.

All five are cut, and the site serves four: the landing's first slide is the
hand-built mock rather than a photograph of the same window, so `01-limits` has
nowhere to go. It is still cut here because the next thing to want it is the
README, and a tool that quietly skipped one of its inputs would be a trap.
"""

import pathlib
import sys

from PIL import Image, ImageDraw

HERE = pathlib.Path(__file__).resolve().parent.parent
SOURCE = HERE / "docs" / "screenshots"
OUT = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "site" / "shots"
OUT.mkdir(parents=True, exist_ok=True)

CAPTION_ENDS = 240          # no window starts above this; every caption ends by it
MEASURED = {"05-minimal": ((391, 313, 1048, 701), 15)}
RADIUS = 10                 # the macOS window corner at this scale


def found_by_saturation(image):
    width, height = image.size
    pixel = image.load()
    left, top, right, bottom = width, height, -1, -1
    for y in range(CAPTION_ENDS, height):
        for x in range(width):
            p = pixel[x, y]
            if max(p) - min(p) < 18:
                left, right = min(left, x), max(right, x)
                top, bottom = min(top, y), max(bottom, y)
    if right < 0:
        raise SystemExit("no neutral pixels below the caption — the shot changed shape")
    # One pixel in on every side: the outermost neutral pixel is the window's
    # own antialiased edge blended with the gradient behind it, and it showed
    # as a violet hairline down the left of the first crop.
    return left + 1, top + 1, right, bottom


for path in sorted(SOURCE.glob("*.webp")):
    image = Image.open(path).convert("RGB")
    box, radius = MEASURED.get(path.stem, (None, RADIUS))
    if box is None:
        box = found_by_saturation(image)

    cut = image.crop(box)
    width, height = cut.size
    mask = Image.new("L", (width, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, width - 1, height - 1],
                                           radius=radius, fill=255)
    out = Image.new("RGBA", (width, height))
    out.paste(cut, mask=mask)
    out.save(OUT / f"{path.stem}.png")
    print(f"  {path.stem}: {width}x{height}")
