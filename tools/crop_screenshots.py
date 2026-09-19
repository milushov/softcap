#!/usr/bin/env python3
"""Cuts the app window out of each App Store screenshot.

    python3 tools/crop_screenshots.py [out-dir]     writes PNGs

Then, for each of the four the site serves:

    cwebp -q 90 -m 6 -alpha_q 100 <name>.png -o site/shots/<name>.webp

The five shots in `docs/screenshots` are marketing images: a saturated gradient,
a baked-in English caption, and the window in the lower two thirds. Neither the
gradient nor the caption belongs on a site that ships ten languages and two
palettes, so only the window is kept — the caption becomes translated text in
the page and the shadow becomes CSS that can differ between light and dark.

Four of the five are found by saturation: the window chrome is neutral and every
pixel of the gradient behind it, shadow included, is a saturated blue or teal.
`05-minimal` is the exception and is measured rather than found — its window is
a vibrancy material that takes the wallpaper's own blue, so it is no more
neutral than the background it sits on. Its edges were read off a luminance
scan: the window's own bright rim runs down x 393 and 1046 and across y 315 and
700, with the shadow's near-black contact line one pixel outside each of them.

All five are cut, and the site serves four: the landing's first slide is the
hand-built mock rather than a photograph of the same window, so `01-limits` has
nowhere to go. It is still cut here because the next thing to want it is the
README, and a tool that quietly skipped one of its inputs would be a trap.

Two things about the corners, both of which showed as black horns on the light
palette before they were fixed.

The mask is drawn at eight times the size and averaged down, because
`ImageDraw.rounded_rectangle` writes 0 or 255 and nothing between: at 1:1 the
arc is a staircase, and a staircase cut through a dark window on a near-white
page is visible at the size the page shows it. Averaging an 8x mask gives each
edge pixel its real coverage, which is what an antialiased edge is.

And the radius is larger than the corner looks. A macOS window corner is a
continuous curve, not a circular arc: it leaves the straight edge earlier than
an arc of the same visual size and sits further from the corner along the
diagonal. A circle drawn at the radius the corner appears to have therefore
passes outside the window for most of the arc, and what it keeps is the shadow
— which is at its darkest and widest exactly there, at the corner. The radii
below are the ones that put the whole arc on the window's own rim; each was
chosen by counting what survives outside it, not by eye.
"""

import pathlib
import sys

from PIL import Image, ImageDraw

HERE = pathlib.Path(__file__).resolve().parent.parent
SOURCE = HERE / "docs" / "screenshots"
OUT = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "site" / "shots"
OUT.mkdir(parents=True, exist_ok=True)

CAPTION_ENDS = 240          # no window starts above this; every caption ends by it
MEASURED = {"05-minimal": ((392, 314, 1048, 701), 36)}
RADIUS = 15                 # the settings window's corner, cut on its own rim
SUPERSAMPLE = 8             # mask resolution, averaged back down for the edge


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


def rounded_mask(size, radius, scale=SUPERSAMPLE):
    """An antialiased rounded rectangle: drawn hard at `scale`, averaged to 1:1."""
    width, height = size
    big = Image.new("L", (width * scale, height * scale), 0)
    ImageDraw.Draw(big).rounded_rectangle(
        [0, 0, width * scale - 1, height * scale - 1],
        radius=radius * scale, fill=255)
    # BOX is an exact area average at an integer reduction, so every edge pixel
    # ends up holding the fraction of itself the shape covers. LANCZOS rings.
    return big.resize((width, height), Image.BOX)


for path in sorted(SOURCE.glob("*.webp")):
    image = Image.open(path).convert("RGB")
    box, radius = MEASURED.get(path.stem, (None, RADIUS))
    if box is None:
        box = found_by_saturation(image)

    cut = image.crop(box)
    out = Image.new("RGBA", cut.size)
    out.paste(cut, mask=rounded_mask(cut.size, radius))
    out.save(OUT / f"{path.stem}.png")
    print(f"  {path.stem}: {cut.size[0]}x{cut.size[1]}")
