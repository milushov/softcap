#!/usr/bin/env bash
# Renders the landing at real phone widths and fails if anything overflows.
#
#   ./site/check-widths.sh              # 320 360 390 430 768 1024
#   ./site/check-widths.sh 320 1440
#
# Headless Chrome on macOS will not make a window narrower than 500 px, in either
# headless mode: `--window-size=320,600` is clamped, the page reports a 500 px
# viewport, and the screenshot comes out 320 px wide because it is scaled. Every
# "phone" render made that way is a 500 px render in disguise, and no media query
# below 500 ever fires. The narrow-screen rule on this page exists to stop the
# window mock scrolling sideways, and until now it was arithmetic rather than
# something anybody had seen.
#
# An iframe carries its own viewport for media queries, so a 320 px iframe in a
# wide window is a true 320 px render. The instrument was checked before being
# trusted: a probe reporting `clientWidth` and two media queries showed 320 with
# both firing in a narrow frame, and 1100 with neither in a wide one.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
# 320 is the narrowest phone worth caring about; 1920 is there because the range
# had a top and nobody had looked above it. Wide is bounded by the 980px wrap, so
# a failure there would need an element wider than the window itself — cheap to
# check and one less untested end.
WIDTHS=${*:-320 360 390 430 768 1024 1440 1920}

# With no widths the page below renders no frames, finds no overflow and prints
# "all clear" — a check that examined nothing, passing. The deploy reads that
# line and ships. Third time this idea has turned up: a filter matching no
# suite, a file walk coming back empty, and now this.
if [ -z "${WIDTHS// /}" ]; then
  echo "no widths to check — that is not the same as nothing being wrong" >&2
  exit 1
fi

[ -x "$CHROME" ] || { echo "Chrome not found; set CHROME" >&2; exit 1; }

# Which pages to render. The landing in the four scripts that break layouts
# differently — English as written, Russian for word length, Arabic for
# direction, Bengali for tall stacked glyphs — and the two longest English
# subpages. Override with PAGES for a one-off look at something else.
PAGES=${PAGES:-index.html ru/index.html ar/index.html bn/index.html faq/index.html limits/claude/index.html}
for PAGE in $PAGES; do
  [ -f "$HERE/$PAGE" ] || { echo "$PAGE is not built — run python3 site/build.py first" >&2; exit 1; }
done

# One working directory, overwritten each run. Nothing is deleted: a stale copy
# of a page is harmless, and a delete in a script is not worth the risk.
WORK="${TMPDIR:-/tmp}/softcap-widths"
mkdir -p "$WORK"

for PAGE in $PAGES; do
echo "$PAGE"
cp "$HERE/$PAGE" "$WORK/page.html"

# The parent reaches into each frame's document directly — with
# --allow-file-access-from-files a file:// parent may read a file:// child, so
# no messaging and no waiting: the parent's load event fires after the frames.
{
  echo '<!doctype html><meta charset="utf-8"><pre id="out">no result</pre>'
  for w in $WIDTHS; do
    echo "<iframe data-w=\"$w\" src=\"page.html\" style=\"width:${w}px;height:8000px;border:0;position:absolute;left:-9999px\"></iframe>"
  done
  cat <<'JS'
<script>
addEventListener('load', () => {
  const lines = []; let bad = 0;
  for (const f of document.querySelectorAll('iframe')) {
    const want = +f.dataset.w;
    let d;
    try { d = f.contentDocument; } catch (e) { lines.push('FAIL ' + want + 'px unreadable'); bad++; continue; }
    const vw = d.documentElement.clientWidth, sw = d.documentElement.scrollWidth;
    const over = [];
    for (const el of d.querySelectorAll('*')) {
      const r = el.getBoundingClientRect();
      if (r.width > vw + 1 || r.right > vw + 1) {
        over.push(el.tagName.toLowerCase()
          + (el.className ? '.' + String(el.className).split(' ')[0] : '')
          + ' ' + Math.round(r.width) + 'px');
      }
    }
    if (vw !== want) { lines.push('FAIL ' + want + 'px rendered at ' + vw); bad++; }
    else if (sw > vw || over.length) {
      lines.push('FAIL ' + want + 'px scrollWidth ' + sw + (over.length ? ' — ' + over.slice(0, 6).join(', ') : ''));
      bad++;
    } else lines.push('ok   ' + want + 'px');
  }
  // Rendered has to match asked-for. A frame that failed to load leaves no
  // line, and a run with no frames at all would otherwise be "all clear".
  const want = document.querySelectorAll('iframe').length;
  const verdict = lines.length !== want
    ? (lines.length + ' of ' + want + ' frames reported — FAILED')
    : (bad ? bad + ' FAILED' : 'all clear');
  document.getElementById('out').textContent = lines.join(' // ') + ' // ' + verdict;
});
</script>
JS
} > "$WORK/frames.html"

# Twice: at the browser's own size, and with a minimum font size forced up.
#
# A reader can raise that in the browser's settings, and it is one of the few
# accessibility controls people genuinely use. At 24 px the appearance switch ran
# 87 px past a 320 px screen and the whole page scrolled sideways — the header was
# a flex row that could not wrap, `~/.codex/sessions` had nowhere to break, and
# the window mock's badge was wider than the window. None of it was visible here,
# because this check rendered at the default size only.
#
# 24 is what a browser calls "very large", and it is the largest size at which
# everything genuinely fits. The bar was briefly set at 32 on the strength of a
# probe that asked whether the *page* scrolled sideways; this check asks the
# stricter and better question — whether any element runs past the edge — and at
# 32 the mock's staleness badge does. It cannot be made not to: a minimum font
# size is a floor CSS may not go under, and a picture of a 322 px window with 32 px
# text inside it does not exist. The clip on `.win` is still worth having past the
# bar, because a reader there gets a cut-off mock rather than a page that scrolls.
for MIN in 0 24; do
  if [ "$MIN" = "0" ]; then
    LABEL="at the default text size"; FONT=()   # empty on purpose
  else
    LABEL="with a ${MIN}px minimum text size"; FONT=(--blink-settings=minimumFontSize=$MIN)
  fi
  echo "  $LABEL"
  OUT=$("$CHROME" --headless=new --disable-gpu --hide-scrollbars \
          --window-size=1400,900 --allow-file-access-from-files \
          ${FONT[@]+"${FONT[@]}"} \
          --dump-dom "file://$WORK/frames.html" 2>/dev/null \
        | sed -n 's/.*<pre id="out">\([^<]*\)<\/pre>.*/\1/p' | head -1)

  [ -n "$OUT" ] || { echo "the check produced no result for $PAGE $LABEL" >&2; exit 1; }
  printf '%s\n' "$OUT" | tr '/' '\n' | sed '/^$/d;s/^ *//;s/^/  /'
  case "$OUT" in
    *FAILED*) echo "  ^ in $PAGE $LABEL" >&2; exit 1 ;;
    *"all clear"*) ;;
    *) echo "unrecognised result for $PAGE $LABEL" >&2; exit 1 ;;
  esac
done
done
