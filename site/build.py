#!/usr/bin/env python3
"""Renders the site from templates and string catalogues.

    python3 site/build.py            rebuild every page in place
    python3 site/build.py --check    rebuild nowhere and fail on any drift

One shell (`src/shell.html`) wraps one body per page (`src/<page>.body.html`,
a slash in a page path becomes a dot in the template name). Every human
string lives in `strings/<lang>.json`; a page renders for a language exactly
when that catalogue file exists, so the ten languages arrive one file at a
time without a flag day. All output is committed: the repository is the
record of what is live, and the pre-commit hook runs `--check` so a template
edit cannot land without its regenerated pages.

Substitution is plain text, standard library only, deterministic:

    {{key}}         the catalogue value
    {{page:K}}      the value of `<page>.K` for the page being rendered
    {{json:key}}    the value, JSON-escaped, for use inside JSON-LD
    {{lang}} {{dir_attr}} {{og_locale}} {{canonical}} {{page_path}} {{root}}
    {{head_extra}}  `src/<page>.head.html`, when the page has one
    {{body}}        the page's body template

A `{{` surviving into output is an error, not a page. Exit codes: 2 when the
catalogues disagree about keys or placeholders, 1 when `--check` finds drift.
"""

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = HERE / "src"
STRINGS = HERE / "strings"

ORIGIN = "https://softcap.app"
LANGS = ["en", "ru", "es", "fr", "ar", "bn", "hi", "id", "pt-BR", "zh-Hans"]
RTL = {"ar"}
OG_LOCALE = {
    "en": "en_US", "ru": "ru_RU", "es": "es_ES", "fr": "fr_FR",
    "ar": "ar_SA", "bn": "bn_BD", "hi": "hi_IN", "id": "id_ID",
    "pt-BR": "pt_BR", "zh-Hans": "zh_CN",
}
PAGES = ["index", "privacy", "support", "terms",
         "faq", "changelog", "limits/claude", "limits/codex"]
ASSETS = ["favicon.ico", "icon.svg", "og.png", "robots.txt", "sitemap.xml"]

# Brand names aside, a reader picks their language by its own name — the
# English gloss is for whoever is helping them find it.
NATIVE = {
    "en": "English", "ru": "Русский", "es": "Español", "fr": "Français",
    "ar": "العربية", "bn": "বাংলা", "hi": "हिन्दी", "id": "Bahasa Indonesia",
    "pt-BR": "Português (Brasil)", "zh-Hans": "中文（简体）",
}
ENGLISH_NAME = {
    "en": "English", "ru": "Russian", "es": "Spanish", "fr": "French",
    "ar": "Arabic", "bn": "Bengali", "hi": "Hindi", "id": "Indonesian",
    "pt-BR": "Portuguese (Brazil)", "zh-Hans": "Chinese (Simplified)",
}


def code_label(lang):
    return lang.split("-")[0].upper()


def alternates(page, langs):
    """The hreflang cluster: one line per rendered language, plus x-default."""
    lines = [f'<link rel="alternate" hreflang="{lang}" '
             f'href="{ORIGIN}/{lang_dir(lang)}{page_path(page)}">'
             for lang in langs]
    lines.append(f'<link rel="alternate" hreflang="x-default" '
                 f'href="{ORIGIN}/{page_path(page)}">')
    return "\n".join(lines)


def picker(page, current, langs):
    """The <details> language picker; empty while only one language exists,
    so no phase of the build ever links to a page that is not there."""
    if len(langs) < 2:
        return ""
    rows = []
    for lang in langs:
        inner = (f'<span class="code">{code_label(lang)}</span>'
                 f'<span class="names"><span>{NATIVE[lang]}</span>'
                 f'<span>{ENGLISH_NAME[lang]}</span></span>')
        if lang == current:
            rows.append(f'        <span class="lang-row" aria-current="true">{inner}</span>')
        else:
            rows.append(f'        <a class="lang-row" lang="{lang}" hreflang="{lang}" '
                        f'href="/{lang_dir(lang)}{page_path(page)}">{inner}</a>')
    body = "\n".join(rows)
    return (f'<details class="lang">\n'
            f'      <summary aria-label="{{{{shell.language}}}}">'
            f'<span>{code_label(current)}</span>'
            f'<bdi dir="ltr">+{len(langs) - 1}</bdi></summary>\n'
            f'      <div class="lang-panel">\n{body}\n      </div>\n'
            f'    </details>')


def die(message, code):
    print(f"build.py: {message}", file=sys.stderr)
    sys.exit(code)


def lang_dir(lang):
    return "" if lang == "en" else lang.lower() + "/"


def page_path(page):
    return "" if page == "index" else page + "/"


def page_key(page):
    return page.replace("/", ".")


def body_template(page):
    return SRC / (page.replace("/", ".") + ".body.html")


def head_template(page):
    path = SRC / (page.replace("/", ".") + ".head.html")
    return path if path.exists() else None


def tokens_of(value):
    """The {{…}} tokens inside a catalogue value, as a sorted list."""
    out, i = [], 0
    while True:
        i = value.find("{{", i)
        if i < 0:
            return sorted(out)
        j = value.find("}}", i)
        if j < 0:
            return sorted(out + [value[i:]])
        out.append(value[i:j + 2])
        i = j + 2


def load_catalogues():
    catalogues = {}
    for lang in LANGS:
        path = STRINGS / f"{lang}.json"
        if path.exists():
            catalogues[lang] = json.loads(path.read_text(encoding="utf-8"))
    if "en" not in catalogues:
        die("strings/en.json is missing — there is no source catalogue", 2)
    base = catalogues["en"]
    for lang, cat in catalogues.items():
        missing = sorted(set(base) - set(cat))
        extra = sorted(set(cat) - set(base))
        if missing or extra:
            die(f"{lang}.json disagrees with en.json on keys "
                f"(missing {missing[:6]}, extra {extra[:6]})", 2)
        for key in base:
            if tokens_of(base[key]) != tokens_of(cat[key]):
                die(f"{lang}.json and en.json disagree on the tokens inside "
                    f"{key!r}", 2)
    return catalogues


def render_page(page, lang, langs, catalogues):
    shell = (SRC / "shell.html").read_text(encoding="utf-8")
    body = body_template(page).read_text(encoding="utf-8")
    head = head_template(page)
    out = shell.replace("{{head_extra}}",
                        head.read_text(encoding="utf-8") if head else "")
    out = out.replace("{{body}}", body)

    directory = lang_dir(lang) + page_path(page)
    depth = directory.count("/")
    substitutions = {
        "{{lang}}": lang,
        "{{dir_attr}}": ' dir="rtl"' if lang in RTL else "",
        "{{og_locale}}": OG_LOCALE[lang],
        "{{canonical}}": f"{ORIGIN}/{directory}",
        "{{page_path}}": page_path(page),
        "{{root}}": "../" * depth,
        "{{lang_prefix}}": lang_dir(lang),
        "{{alternates}}": alternates(page, langs),
        "{{picker}}": picker(page, lang, langs),
    }
    for token, value in substitutions.items():
        out = out.replace(token, value)

    catalogue = catalogues[lang]
    prefix = page_key(page) + "."
    # Longest keys first, so a key that begins with another key's name can
    # never be half-replaced through it.
    for key in sorted(catalogue, key=len, reverse=True):
        value = catalogue[key]
        out = out.replace("{{json:" + key + "}}",
                          json.dumps(value, ensure_ascii=False)[1:-1])
        if key.startswith(prefix):
            out = out.replace("{{page:" + key[len(prefix):] + "}}", value)
        out = out.replace("{{" + key + "}}", value)

    at = out.find("{{")
    if at >= 0:
        line = out.count("\n", 0, at) + 1
        die(f"{directory or './'}index.html line {line}: unresolved "
            f"{out[at:at + 60]!r}", 2)
    return out


def rendered_tree(catalogues):
    """Every generated file, as {relative path: content}."""
    langs = [lang for lang in LANGS if lang in catalogues]
    pages = [page for page in PAGES if body_template(page).exists()]
    tree = {}
    for lang in langs:
        for page in pages:
            path = lang_dir(lang) + page_path(page) + "index.html"
            tree[path] = render_page(page, lang, langs, catalogues)

    urls = [f"{ORIGIN}/{lang_dir(lang)}{page_path(page)}"
            for page in pages for lang in langs]
    if len(langs) == 1:
        entries = "\n".join(f"  <url><loc>{url}</loc></url>"
                            for url in sorted(urls))
        tree["sitemap.xml"] = (
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
            f"{entries}\n</urlset>\n")
    else:
        # The multilingual form: every entry names every language version,
        # so a search engine learns the whole cluster from any one of them.
        blocks = []
        for page in pages:
            alternates = "".join(
                f'\n    <xhtml:link rel="alternate" hreflang="{lang}" '
                f'href="{ORIGIN}/{lang_dir(lang)}{page_path(page)}"/>'
                for lang in langs) + (
                f'\n    <xhtml:link rel="alternate" hreflang="x-default" '
                f'href="{ORIGIN}/{page_path(page)}"/>')
            for lang in langs:
                url = f"{ORIGIN}/{lang_dir(lang)}{page_path(page)}"
                blocks.append(f"  <url><loc>{url}</loc>{alternates}\n  </url>")
        tree["sitemap.xml"] = (
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"\n'
            '        xmlns:xhtml="http://www.w3.org/1999/xhtml">\n'
            + "\n".join(blocks) + "\n</urlset>\n")

    served = sorted(set(tree) | set(ASSETS))
    tree["manifest.txt"] = "".join(f"{path}\n" for path in served)
    return tree


def main():
    check = "--check" in sys.argv[1:]
    catalogues = load_catalogues()
    tree = rendered_tree(catalogues)

    if check:
        drifted = []
        for path, content in sorted(tree.items()):
            on_disk = HERE / path
            if not on_disk.exists() or on_disk.read_text(encoding="utf-8") != content:
                drifted.append(path)
        if drifted:
            for path in drifted:
                print(f"site/{path} is not what the sources render", file=sys.stderr)
            die("run python3 site/build.py and commit the result", 1)
        print(f"build.py --check: {len(tree)} files match their sources")
        return

    for path, content in sorted(tree.items()):
        target = HERE / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")
    print(f"build.py: wrote {len(tree)} files "
          f"({sum(1 for p in tree if p.endswith('index.html'))} pages, "
          f"{len(catalogues)} languages)")


if __name__ == "__main__":
    main()
