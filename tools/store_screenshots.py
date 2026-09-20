#!/usr/bin/env python3
"""Takes the App Store screenshots, in every language the app speaks.

    make screenshots                       # build the app this photographs
    python3 tools/store_screenshots.py     # 45 photographs, 50 pictures, ~6 min

Five screens, nine languages, one build. The language is a setting, so a run
hands it to the app in `SOFTCAP_SHOT_LANG` and the app draws itself in it;
`SOFTCAP_SHOT` names the screen. Nothing is clicked — see `stageScreenshot` in
App/SoftcapApp.swift, which opens whichever screen was asked for.

Each picture is the window itself photographed by its window id, composited on
the gradient by tools/store_shot.swift under the caption the website already
uses for the same screen. Both halves matter:

  By id, not by rectangle. `screencapture -R x,y,w,h` photographs the screen
  region, which is whatever happens to be in front — the first run of this
  produced five photographs of a terminal. Softcap is an accessory app and
  cannot be relied on to come to the front, so `-l<id>` asks for the window
  rather than the place it is standing.

  The caption comes from site/strings/<lang>.json, the same key the landing
  page's gallery uses. A screenshot in the store and a slide on the website are
  then one sentence translated once, and `SiteCataloguesAgree` is already
  holding those ten files to the same key set. The one-word headline above it
  is the store's alone — `Clear`, `Together`, `Counted`, `Ahead`, `Quiet` —
  and lives in store/headlines.json in the same ten languages.

The output is a directory per App Store locale, named the way App Store Connect
names them, holding five 2880×1800 PNGs each — the size Apple asks for a Mac
screenshot. They are not committed: fifty of them are 400 MB, and this script
is what the repository keeps instead.
"""

import json
import pathlib
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent.parent
APP = HERE / "build-shots/Build/Products/Debug/Softcap.app/Contents/MacOS/Softcap"
RENDERER = HERE / "tools/store_shot.swift"

# The five screens, in the order the store shows them. Accounts is second
# rather than fifth on purpose: several Claude and Codex accounts in one list is
# the thing no competitor's first screenshots show, and the second screenshot is
# the last one most people see.
SCREENS = [
    ("01-limits", "window", "shot1"),
    ("02-accounts", "accounts", "shot2"),
    ("03-notifications", "notifications", "shot4"),
    ("04-statistics", "statistics", "shot3"),
    ("05-minimal", "minimal", "shot5"),
]

# App Store Connect's locale on the left, the app's own language code — and the
# website's catalogue name — on the right. Spanish and English are each two
# storefront locales sharing one translation; Bengali is missing because App
# Store Connect has no Bengali, which is written down in docs/DECISIONS.md.
LOCALES = {
    "en-US": "en",
    "ru": "ru",
    "es-ES": "es",
    "es-MX": "es",
    "fr-FR": "fr",
    "pt-BR": "pt-BR",
    "hi": "hi",
    "id": "id",
    "ar-SA": "ar",
    "zh-Hans": "zh-Hans",
}

RIGHT_TO_LEFT = {"ar"}


def build(source: pathlib.Path, out: pathlib.Path) -> pathlib.Path:
    """Compiles one of the two Swift helpers — once per run, and again when the
    source has changed since: a binary kept from last week's run draws last
    week's design and says nothing about it."""
    binary = out / source.stem
    if not binary.exists() or binary.stat().st_mtime < source.stat().st_mtime:
        subprocess.run(["swiftc", "-O", str(source), "-o", str(binary)], check=True)
    return binary


def capture(language: str, screen: str, into: pathlib.Path, finder: pathlib.Path) -> pathlib.Path:
    """Runs the app showing one screen in one language, and photographs it."""
    into.parent.mkdir(parents=True, exist_ok=True)
    environment = {
        "SOFTCAP_SHOT": "window" if screen == "minimal" else screen,
        "SOFTCAP_SHOT_MINIMAL": "1" if screen == "minimal" else "0",
        "SOFTCAP_SHOT_LANG": language,
        "PATH": "/usr/bin:/bin",
        "HOME": str(pathlib.Path.home()),
    }
    app = subprocess.Popen([str(APP)], env=environment)
    try:
        # The window is built after launch and laid out over several frames. The
        # id is asked for until it exists, and then the picture waits: a capture
        # fired at the first frame catches the window mid-layout, with the
        # sidebar drawn and the pane still empty.
        # By pid, both here and below: the copy in /Applications is also called
        # Softcap, and when it has a window open, "the largest window named
        # Softcap" is whichever of the two is bigger. Fifty pictures of the
        # installed copy's Updates pane were made that way.
        found = ""
        for _ in range(60):
            time.sleep(0.4)
            found = subprocess.run([str(finder), str(app.pid)], capture_output=True,
                                   text=True).stdout.strip()
            if found:
                break
        if not found:
            raise SystemExit(f"no window appeared for {language}/{screen}")
        # Brought to the front, or the window is photographed inactive: three
        # grey buttons in the corner where the originals have a red one. The
        # app activates itself on launch, and whichever terminal runs this
        # takes the focus straight back.
        subprocess.run(["osascript", "-e",
                        'tell application "System Events" to set frontmost of '
                        f'(first process whose unix id is {app.pid}) to true'],
                       capture_output=True)
        time.sleep(1.6)
        found = subprocess.run([str(finder), str(app.pid)], capture_output=True,
                               text=True).stdout.strip()
        number = found.split()[0]
        # -o leaves the shadow out: it is drawn again at composite time, where it
        # can be tuned to the background rather than to whatever was behind the
        # window on the day.
        subprocess.run(["screencapture", "-x", "-o", f"-l{number}", str(into)], check=True)
    finally:
        app.terminate()
        try:
            app.wait(timeout=10)
        except subprocess.TimeoutExpired:
            app.kill()
    return into


def strings(language: str) -> dict:
    return json.loads((HERE / f"site/strings/{language}.json").read_text(encoding="utf-8"))


def compose(shot: pathlib.Path, screen: str, headline: str, caption: str, language: str,
            into: pathlib.Path, renderer: pathlib.Path) -> None:
    """Puts one photographed window on its gradient, under its caption."""
    into.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(renderer), str(shot), str(into), screen, language, headline, caption],
                   check=True)


def main() -> int:
    if not APP.exists():
        print(f"no screenshot build at {APP} — run `make screenshots` first", file=sys.stderr)
        return 1
    out = (pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1
           else HERE / "build-shots/store")
    work = out / ".work"
    work.mkdir(parents=True, exist_ok=True)
    finder = build(HERE / "tools/window_id.swift", work)
    renderer = build(RENDERER, work)

    # One capture per language, shared by the locales that speak it: es-ES and
    # es-MX are the same Spanish, and photographing it twice would only mean two
    # chances for the clock in the corner to differ.
    headlines = json.loads((HERE / "store/headlines.json").read_text(encoding="utf-8"))
    for language in sorted(set(LOCALES.values())):
        catalogue = strings(language)
        for name, screen, key in SCREENS:
            raw = capture(language, screen, work / "raw" / language / f"{name}.png", finder)
            for locale, spoken in LOCALES.items():
                if spoken != language:
                    continue
                compose(raw, name, headlines[name][language],
                        catalogue[f"index.{key}_caption"], language,
                        out / locale / f"{name}.png", renderer)
            print(f"  {language}/{name}", flush=True)

    print(f"written to {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
