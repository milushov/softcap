#!/usr/bin/env python3
"""Fills in the translation catalogues.

Reads JSON of the form {"English key": {"ru": "...", "ar": "...", ...}} from
standard input and appends the missing keys to all ten catalogues. Keys already
present are left alone, so running the script twice is harmless.

Every language but English must be present for every key. A missing one is
refused rather than filled with the English text, which would leave a catalogue
that looks translated and is not.

The English catalogue is filled with the key itself: keys are English phrases.
"""
import json
import pathlib
import re
import sys

BASE = pathlib.Path(__file__).resolve().parent.parent / \
    "Packages/Core/Sources/StatusUI/Resources"
LANGS = ["en", "zh-Hans", "hi", "es", "ar", "fr", "bn", "pt-BR", "ru", "id"]


def escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace('"', '\\"')


def existing_keys(path: pathlib.Path) -> set[str]:
    if not path.exists():
        return set()
    return set(re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=', path.read_text(encoding="utf-8"), re.M))


def main() -> int:
    additions = json.load(sys.stdin)

    # A language left out of the input used to be filled with the English key,
    # silently. The catalogues then stayed the same size, every key lined up, no
    # orphan appeared — and nine languages showed English while every guard in
    # the repository was satisfied. Nothing downstream can tell that apart from a
    # word that is genuinely the same in both, so it has to be refused here.
    #
    # Passing the English text explicitly is still allowed: that is the caller
    # saying so, which is different from forgetting.
    missing = [
        f"{key!r}: {', '.join(sorted(gaps))}"
        for key, translations in additions.items()
        if (gaps := [l for l in LANGS if l != "en" and l not in translations])
    ]
    if missing:
        print("no translation for:", file=sys.stderr)
        for line in missing:
            print(f"  {line}", file=sys.stderr)
        print("\nsupply every language, or the English text where it is the same",
              file=sys.stderr)
        return 1

    added = 0

    for lang in LANGS:
        path = BASE / f"{lang}.lproj" / "Localizable.strings"
        path.parent.mkdir(parents=True, exist_ok=True)
        have = existing_keys(path)

        lines = []
        for key, translations in additions.items():
            if key in have:
                continue
            value = key if lang == "en" else translations[lang]
            lines.append(f'"{escape(key)}" = "{escape(value)}";')

        if lines:
            with path.open("a", encoding="utf-8") as handle:
                handle.write("\n".join(lines) + "\n")
            added = max(added, len(lines))

    print(f"keys added: {added}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
