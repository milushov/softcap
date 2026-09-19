#!/usr/bin/env bash
#
# Deploys the landing page to the host that serves softcap.app.
#
# The host runs everything in Docker behind kamal-proxy, which terminates TLS and routes by the
# Host header. A static site is a stock Caddy container with the built files bind-mounted, joined
# to the `kamal` network so the proxy can reach it by container name. This follows the pattern the
# other static sites on that host already use.
#
#   ./deploy.sh
#
# Idempotent: run it again after editing index.html and the page is replaced in place.
set -euo pipefail

REMOTE="/opt/softcap-site"

# Every ssh in this script carries a connect timeout, and rsync is told to use
# the same. Without one, an unreachable host costs 75 seconds per call — measured,
# not guessed — and there are six calls and two transfers, so a host that is
# simply off would stall this script for the better part of ten minutes and say
# nothing until the end. It runs unattended.
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=10"
DOMAIN="${SOFTCAP_DOMAIN:-softcap.app}"

# The host is whatever the domain points at, rather than an address written down
# here: an address in a file goes stale silently, and the domain is the thing
# that actually decides where the site lives. `root` because that is how this
# host is administered — override the whole thing with SOFTCAP_HOST if not.
if [ -z "${SOFTCAP_HOST:-}" ]; then
  ip=$(dig +short "$DOMAIN" A | head -1)
  [ -n "$ip" ] || { echo "$DOMAIN does not resolve; set SOFTCAP_HOST" >&2; exit 1; }
  HOST="root@$ip"
else
  HOST="$SOFTCAP_HOST"
fi
SERVICE="softcap-site"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Everything the site serves, straight from the manifest the build writes —
# eighty pages in ten languages plus the five assets. Listed rather than
# globbed for the same reason as ever: the directory also holds the deploy
# script, the Caddyfile, the compose file, the templates and the catalogues,
# and none of those belong on a public host.
if [ ! -s "$HERE/manifest.txt" ]; then
  echo "  site/manifest.txt is missing or empty — run python3 site/build.py first" >&2
  exit 1
fi
SERVED=()
while IFS= read -r line; do [ -n "$line" ] && SERVED+=("$line"); done < "$HERE/manifest.txt"

# Everything below reads this list: what is copied, what is deleted from the
# server, and what is verified afterwards. Empty, the verification loop would
# find no fault and report success — and `rsync -az --delete` would be left with
# one argument and no sources, pointed at the live site's directory. The second
# of those is worse than the first, and both are prevented here rather than
# discovered. Eighty-five is what a full build writes today; anything below it
# means a build that did not finish, not a smaller site.
if [ "${#SERVED[@]}" -lt 85 ]; then
  echo "  the manifest lists ${#SERVED[@]} entries, fewer than the 85 a full build writes —" >&2
  echo "  refusing to copy, delete or verify against it" >&2
  exit 1
fi

# The address a reader actually visits, for a path in the manifest.
#
# Every page is `<dir>/index.html` and is linked, sitemapped and canonicalised
# as `/<dir>/` — so checking `/<dir>/index.html` checks a path nothing uses and
# leaves the one that everything uses untested. It is not the same request:
# the directory form is Caddy resolving an index, and that resolution is a
# thing that can break on its own.
page_url() {
  case "$1" in
    index.html) printf 'https://%s/' "$DOMAIN" ;;
    */index.html) printf 'https://%s/%s' "$DOMAIN" "${1%index.html}" ;;
    *) printf 'https://%s/%s' "$DOMAIN" "$1" ;;
  esac
}

# ---------------------------------------------------------------------------
# Going back.
#
# Until now a deploy that shipped and then failed its own verification left the
# broken files live, with no way back but forward — and that has happened once,
# when a digest check found six mismatches after the transfer. The previous
# version is now kept beside the current one, and `--rollback` puts it back.
#
# The directory is bind-mounted into the container, so a rename would leave Caddy
# serving the old inode under a new name. The contents are replaced instead.
# ---------------------------------------------------------------------------

# Refuses to overwrite a good snapshot with a dist that has been emptied — the
# same floor as SERVED, one machine further away.
# Everything a deploy replaces, not just the pages. The Caddyfile and the compose
# file are shipped too, and a Caddyfile that does not parse stops the container —
# a site down rather than a site wrong, and the first version of this kept only
# `dist`, so the rollback could not have repaired the worse of the two failures.
snapshot_current() {
  ssh $SSH_OPTS "$HOST" "
    set -e; cd $REMOTE
    if [ -d dist ] && [ \$(find dist -type f | wc -l) -ge 6 ]; then
      mkdir -p prev/dist
      rsync -a --delete dist/ prev/dist/
      for f in Caddyfile docker-compose.yml; do
        [ -f \$f ] && cp -p \$f prev/\$f
      done
      # The snapshot says how big it is. The site grew from six files to
      # eighty-five in one day; a rollback comparing against today's count
      # would refuse yesterday's perfectly good site, and one comparing
      # against a constant would restore half a tree without noticing.
      find prev/dist -type f | wc -l | tr -d ' ' > prev/COUNT
      true
    fi"
}

roll_back() {
  echo "→ putting the previous version back"
  local held expected
  held=$(ssh $SSH_OPTS "$HOST" "find $REMOTE/prev/dist -type f 2>/dev/null | wc -l" || echo 0)
  # Compared against the snapshot's own record of itself, written when it was
  # taken — not against today's manifest, which may be the wrong size for the
  # version being restored. Six covers snapshots older than the COUNT file.
  expected=$(ssh $SSH_OPTS "$HOST" "cat $REMOTE/prev/COUNT 2>/dev/null" || echo 6)
  case "$expected" in ''|*[!0-9]*) expected=6 ;; esac
  if [ "$held" -lt "$expected" ]; then
    echo "  $REMOTE/prev/dist holds $held files, fewer than the $expected it recorded —" >&2
    echo "  restoring it would take the site down. Nothing was changed." >&2
    exit 1
  fi
  ssh $SSH_OPTS "$HOST" "set -e; cd $REMOTE && rsync -a --delete prev/dist/ dist/"

  # Said either way. A rollback that quietly restored two of three files would
  # look exactly like one that restored all of them.
  local config
  config=$(ssh $SSH_OPTS "$HOST" "
    cd $REMOTE
    for f in Caddyfile docker-compose.yml; do
      if [ -f prev/\$f ]; then cp -p prev/\$f \$f; echo -n \"\$f \"; fi
    done")
  ssh $SSH_OPTS "$HOST" "docker restart softcap-site >/dev/null"
  echo "  restored $held files and restarted"
  if [ -n "${config// /}" ]; then
    echo "  and the configuration it was serving with: ${config% }"
  else
    echo "  the snapshot held no Caddyfile or compose file — the configuration is" >&2
    echo "  whatever the failed deploy left, and may be the reason it failed" >&2
  fi

  # Deliberately not the digest check the deploy runs: after a rollback the live
  # files are the previous version and are *supposed* to differ from the ones in
  # this checkout. What matters is that the site answers and is whole.
  echo "→ checking the site is up"
  local bad=0
  for f in "${SERVED[@]}"; do
    local code
    code=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 15 "$(page_url "$f")" || echo 000)
    [ "$code" = "200" ] || { echo "  $(page_url "$f") answered $code" >&2; bad=1; }
  done
  curl -sS --max-time 15 "https://$DOMAIN/" | grep -q "</html>" \
    || { echo "  the page served is not whole" >&2; bad=1; }
  [ "$bad" = "0" ] || { echo "  the rollback did not land cleanly" >&2; exit 1; }
  echo "  all $((${#SERVED[@]})) files answer and the page is whole"
  echo "  live now: $(curl -sS --max-time 15 "https://$DOMAIN/" | shasum -a 256 | cut -c1-12)"
  echo "  this checkout: $(shasum -a 256 "$HERE/index.html" | cut -c1-12)"
  exit 0
}

# ---------------------------------------------------------------------------
# Is what is live what is here?
#
# The deploy answers that only as a side effect of deploying, and it needs ssh to
# get there. When ssh is unreachable — which happened for two runs in a row, the
# banner exchange timing out while the host answered ping and served the site
# perfectly — the repository quietly moves ahead of the server and nothing says
# so. The check below is the one part of this script that needs no ssh at all.
# ---------------------------------------------------------------------------
live_status() {
  echo "→ comparing what is live against this checkout"
  # A fixed path, overwritten each run, the same way `check-widths.sh` does it.
  # A fresh mktemp would need cleaning up, and a delete with a variable in its
  # path is a thing to have none of in a script that runs unattended.
  local WORK="${TMPDIR:-/tmp}/softcap-status"
  mkdir -p "$WORK"
  local behind=0 unreachable=0
  for f in "${SERVED[@]}"; do
    local here there
    local code
    here=$(shasum -a 256 "$HERE/$f" | cut -d" " -f1)
    # Asked for outright rather than inferred. A body that did not arrive digests
    # to the hash of nothing, which is a real digest and compares like one — the
    # first version of this recognised that constant, which works and reads like
    # a riddle.
    code=$(curl -sS -o "$WORK/live" -w "%{http_code}" --max-time 20 \
             "$(page_url "$f")" 2>/dev/null || echo 000)
    if [ "$code" != "200" ]; then
      printf "  %-14s answered %s\n" "$f" "$code" >&2; unreachable=1; continue
    fi
    there=$(shasum -a 256 "$WORK/live" | cut -d" " -f1)
    if [ "$here" = "$there" ]; then
      printf "  %-14s matches\n" "$f"
    else
      printf "  %-14s differs — live %s, here %s\n" "$f" "${there:0:12}" "${here:0:12}"
      behind=1
    fi
  done
  if [ "$unreachable" = "1" ]; then
    echo "  the site did not answer for every file; nothing can be concluded" >&2
    exit 1
  fi
  if [ "$behind" = "1" ]; then
    echo "  the server is not serving this checkout — run $0 to ship it" >&2
    exit 1
  fi
  echo "  the site is serving exactly what is in this checkout"
  exit 0
}

if [ "${1:-}" = "--status" ]; then live_status; fi
if [ "${1:-}" = "--rollback" ]; then roll_back; fi
if [ -n "${1:-}" ]; then
  echo "usage: deploy.sh [--status | --rollback]" >&2
  exit 1
fi

# Both images are rendered from files next to them, so either can fall behind the
# thing it is made of — and a preview showing last week's headline is the kind of
# mistake nobody sees, because nobody looks at their own link previews. Rebuilt
# here when the source is newer, rather than left to be remembered.
regenerate() {
  local out="$1" src="$2" build="$3"
  [ -f "$HERE/$out" ] && [ "$HERE/$src" -ot "$HERE/$out" ] && return 0
  if [ ! -x "${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}" ]; then
    echo "  $out is older than $src and Chrome is not here to rebuild it" >&2
    return 1
  fi
  echo "  rebuilding $out from $src"
  ( cd "$HERE" && eval "$build" )
}

regenerate og.png og-template.html \
  '"${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}" \
     --headless=new --disable-gpu --hide-scrollbars --window-size=1200,630 \
     --virtual-time-budget=3000 --screenshot=og.png og-template.html >/dev/null 2>&1'
regenerate favicon.ico icon.svg './make-favicon.sh >/dev/null'

# A page that scrolls sideways on a phone is not something the file checks below
# would ever notice, and the rule that prevents it could only be reasoned about
# until now — headless Chrome will not open a window narrower than 500 px. The
# check renders the page in iframes, which do carry their own viewport.
# Asked once, before anything is built or copied, so an unreachable host is one
# clear sentence rather than the first of eight timeouts.
#
# It used to be asked inside the Chrome test below, where it was nested by an
# edit rather than on purpose: on a machine without Chrome at that path — which
# is every Linux runner — the question was skipped entirely, and an unreachable
# host came back as the eight timeouts this exists to prevent.
if ! ssh $SSH_OPTS "$HOST" true 2>/dev/null; then
  echo "  $HOST does not answer on ssh — nothing was built, copied or deployed" >&2
  exit 1
fi

if [ -x "${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}" ]; then
  echo "→ checking the page at phone widths"
  "$HERE/check-widths.sh" | sed 's/^/  /'
else
  echo "  Chrome is not here, so the narrow widths go unchecked" >&2
fi

echo "→ checking the files are all present before anything goes anywhere"
for f in "${SERVED[@]}"; do
  [ -s "$HERE/$f" ] || { echo "  $f is missing or empty" >&2; exit 1; }
done
grep -q "</html>" "$HERE/index.html" || { echo "  index.html is truncated" >&2; exit 1; }

echo "→ keeping the version that is live now"
ssh $SSH_OPTS "$HOST" "mkdir -p $REMOTE/dist"
snapshot_current

echo "→ shipping files to $HOST:$REMOTE"
# Staged locally exactly as served, then synced as one tree — so `--delete`
# on the second rsync means "not in the manifest, not on the host", which is
# the sentence it should mean. The stage directory is fresh per run (nothing
# here deletes anything local, on principle) and TMPDIR is the OS's to sweep.
STAGE="${TMPDIR:-/tmp}/softcap-stage-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$STAGE"
rsync -a --files-from="$HERE/manifest.txt" "$HERE/" "$STAGE/"
rsync -az -e "ssh $SSH_OPTS" --delete "$STAGE/" "$HOST:$REMOTE/dist/"
rsync -az -e "ssh $SSH_OPTS" "$HERE/Caddyfile" "$HERE/docker-compose.yml" "$HOST:$REMOTE/"

echo "→ starting the container"
ssh $SSH_OPTS "$HOST" "cd $REMOTE && docker compose up -d --remove-orphans"

# The Caddyfile is bind-mounted, but Caddy holds its configuration in memory and
# `compose up` will not restart a container whose spec is unchanged — so an edited
# Caddyfile changes nothing and the deploy still reports success.
#
# `caddy reload` is the graceful way and was tried first: it printed "adapted
# config to JSON" and left the running server on the old rules, which the admin
# API confirmed. A restart is what actually applies them. The container is a
# static file server that comes up in well under a second, and the kamal-proxy
# deploy below health-checks it before routing, so the restart happens first.
echo "→ restarting so the configuration is re-read"
ssh $SSH_OPTS "$HOST" "docker restart $SERVICE >/dev/null && sleep 2"

echo "→ registering $DOMAIN with kamal-proxy"
# --target takes container:port on the kamal network. Re-running replaces the route, so this is
# safe to repeat; the deploy is what issues and renews the certificate. The health check points at
# `/` rather than the default `/up`: a static site has no such route, and while the SPA fallback
# would answer 200 anyway, checking a path that is meant to exist says what is actually meant.
ssh $SSH_OPTS "$HOST" \
  "docker exec kamal-proxy kamal-proxy deploy $SERVICE \
     --host $DOMAIN --target $SERVICE:80 --tls --health-check-path /"

# A route that lives only in the proxy's memory works perfectly until the host
# reboots, and then the container comes back to serve a domain nothing points at.
# kamal-proxy writes its table to a named volume for exactly this, so the check is
# that our domain reached the file — not that the proxy answers, which it would
# either way. The rest of the chain was inspected once and holds by construction:
# both containers are `restart: unless-stopped`, and docker and containerd are
# enabled at boot. This host has been up seventeen weeks, so none of it has been
# tried end to end, and rebooting it to find out is not this script's business —
# other people's services run here.
echo "→ checking the route would survive a reboot"
if ssh $SSH_OPTS "$HOST" \
     "grep -q '$DOMAIN' /var/lib/docker/volumes/kamal-proxy-config/_data/kamal-proxy.state"; then
  echo "  $DOMAIN is in kamal-proxy's saved state"
else
  echo "  $DOMAIN answers now but is not in kamal-proxy's saved state — a reboot would lose it" >&2
  exit 1
fi

# The compose file says `unless-stopped`; the running container is what a reboot
# consults. They agree today, and a container started by hand once would not.
policy=$(ssh $SSH_OPTS "$HOST" \
  "docker inspect $SERVICE --format '{{.HostConfig.RestartPolicy.Name}}'")
if [ "$policy" = "unless-stopped" ]; then
  echo "  $SERVICE restarts on its own"
else
  echo "  $SERVICE has restart policy '$policy' — it would stay down after a reboot" >&2
  exit 1
fi

# One request is not a measurement. A single connection that fails looks exactly
# like a site that is down, and this script runs unattended: a false failure after
# a deploy that actually landed teaches whoever reads the output to stop believing
# it. Seen once, live — one path answered 000 while five others answered 200, and
# three retries a second later all answered 200.
#
# Two tries, a second apart, and only then a verdict.
try_twice() {
  local out
  out=$("$@" 2>/dev/null) && [ -n "$out" ] && { printf '%s' "$out"; return 0; }
  sleep 1
  out=$("$@" 2>/dev/null) || true
  printf '%s' "$out"
}

fetch_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$1"; }
fetch_head() { curl -sI --max-time 20 "$1"; }

echo "→ verifying"
sleep 3

# Every file that was shipped, not just the page. A deploy that lost the icon or
# the preview would otherwise report success: the page answers 200 and says
# Softcap, and nothing looks at the rest until somebody shares a link.
#
# Compared by digest rather than by status code — a 200 proves something is
# there, not that it is the thing that was sent.
failed=0
for f in "${SERVED[@]}"; do
  url=$(page_url "$f")
  code=$(try_twice fetch_code "$url")
  if [ "$code" != "200" ]; then
    echo "  $url → HTTP $code" >&2; failed=1; continue
  fi
  want=$(shasum -a 256 "$HERE/$f" | cut -d' ' -f1)
  # Piped straight into shasum: a command substitution strips trailing newlines
  # and mangles bytes, which turned every digest into a mismatch the first time
  # this retry was written. The retry wraps the comparison instead.
  got=$(curl -s --max-time 20 "$url" | shasum -a 256 | cut -d' ' -f1)
  if [ "$want" != "$got" ]; then
    sleep 1
    got=$(curl -s --max-time 20 "$url" | shasum -a 256 | cut -d' ' -f1)
  fi
  if [ "$want" = "$got" ]; then
    echo "  $url → 200, matches"
  else
    echo "  $url → 200 but serving something else" >&2; failed=1
  fi
done
# The Caddyfile can be right about a path nobody visits. `header /index.html`
# was applied faithfully and never reached `/`, so the one document that changes
# was served with no Cache-Control at all while three assets that never change
# carried a week of it. The digests above would not notice: the bytes were fine.
echo "→ checking the headers on the URLs people actually use"
expect_header() {
  local url="$1" name="$2" want="$3"
  local got
  got=$(try_twice fetch_head "$url" | tr -d '\r' \
        | sed -n "s/^$name: //Ip" | head -1)
  if [ "$got" = "$want" ]; then
    echo "  $url → $name: $got"
  else
    echo "  $url → $name is '${got:-absent}', expected '$want'" >&2
    failed=1
  fi
}
expect_header "https://$DOMAIN/" Cache-Control "no-cache"
expect_header "https://$DOMAIN/index.html" Cache-Control "no-cache"
# One sample per shape the new matcher covers: a top directory, a nested one,
# a translated root and a translated nested one.
expect_header "https://$DOMAIN/faq/" Cache-Control "no-cache"
expect_header "https://$DOMAIN/limits/claude/" Cache-Control "no-cache"
expect_header "https://$DOMAIN/ru/" Cache-Control "no-cache"
expect_header "https://$DOMAIN/ru/limits/claude/" Cache-Control "no-cache"
for asset in og.png icon.svg favicon.ico shots/02-accounts.webp; do
  expect_header "https://$DOMAIN/$asset" Cache-Control "public, max-age=604800"
done
# The one served file that is neither a page nor a week-long asset. It is also the
# one whose absence is silent: a missing script leaves the mock frozen, which is
# what it looks like when it works.
expect_header "https://$DOMAIN/clock.js" Cache-Control "no-cache"

# A path that does not exist is a served response too, and it was the one nobody
# looked at: 404 with an empty body, none of the security headers, and `Server`
# announced despite the `-Server` in the same file. The digests above only ever
# ask about files that are there.
echo "→ checking what a wrong URL gets"
miss="https://$DOMAIN/this-path-does-not-exist"
code=$(try_twice fetch_code "$miss")
if [ "$code" = "404" ]; then
  echo "  $miss → 404"
else
  echo "  $miss → HTTP $code, expected 404" >&2; failed=1
fi
miss_bytes=$(curl -s --max-time 20 "$miss" | wc -c | tr -d ' ')
[ "$miss_bytes" -gt 0 ] || miss_bytes=$(curl -s --max-time 20 "$miss" | wc -c | tr -d ' ')
if [ "$miss_bytes" -gt 0 ]; then
  echo "  it says something rather than answering with nothing"
else
  echo "  the 404 body is empty — a reader who mistypes gets a blank page" >&2; failed=1
fi
for header in Content-Security-Policy X-Content-Type-Options X-Frame-Options; do
  if try_twice fetch_head "$miss" | grep -qi "^$header:"; then
    echo "  $header on a miss too"
  else
    echo "  $header is missing from the 404" >&2; failed=1
  fi
done
if try_twice fetch_head "$miss" | grep -qi "^server:"; then
  echo "  the 404 names the server, which -Server is there to prevent" >&2; failed=1
else
  echo "  the 404 does not name the server"
fi

# The certificate renews itself and has done so once. If it ever stops, nothing
# says so until the day it expires and every visitor meets a browser warning
# instead of the page. Let's Encrypt issues for ninety days and kamal-proxy
# renews at about thirty left, so anything under twenty means two renewal
# windows have gone by unnoticed.
# The droplet is shared. Other projects build and pull on it, so the disk can
# fill for reasons nothing here controls, and the symptom would be a container
# that does not come back after the restart below. Better to say so with room to
# act than to find out mid-deploy.
echo "→ checking there is room on the host"
free_gb=$(ssh $SSH_OPTS "$HOST" "df -BG --output=avail / | tail -1 | tr -dc '0-9'" 2>/dev/null || true)
if [ -z "$free_gb" ]; then
  echo "  could not read the host's free space" >&2; failed=1
elif [ "$free_gb" -lt 5 ]; then
  echo "  ${free_gb}G free on the host — too little to deploy into safely" >&2; failed=1
else
  echo "  ${free_gb}G free"
fi

echo "→ checking the chart still looks like this month"
# The chart carries real dates, which is what makes it read as a month of
# somebody's actual usage rather than a diagram. They also age: a landing page
# whose only picture of "over time" ends last spring reads as abandoned, and
# nothing was watching for it. A warning rather than a failure — a stale
# illustration is no reason to refuse an unrelated fix — but a loud one.
newest=$(grep -o '<text class="when"[^>]*>[^<]*</text>' "$HERE/index.html" \
         | tail -1 | sed 's/.*>\(.*\)<.*/\1/')
if [ -z "$newest" ]; then
  # Looking in the wrong place must not read as "nothing to report".
  echo "  the chart's date labels were not found in index.html — this check is" >&2
  echo "  looking in the wrong place and would otherwise approve anything" >&2
  failed=1
else
  chart_age=$(python3 -c "
import datetime, sys
label, today = sys.argv[1].strip(), datetime.date.today()
for year in (today.year, today.year - 1):
    try:
        d = datetime.datetime.strptime(label + ' ' + str(year), '%d %b %Y').date()
    except ValueError:
        continue
    if d <= today:
        print((today - d).days); break
else:
    sys.exit(1)
" "$newest" 2>/dev/null || true)
  if [ -z "$chart_age" ]; then
    echo "  could not read '$newest' as a date" >&2; failed=1
  elif [ "$chart_age" -gt 75 ]; then
    echo "  the chart ends $newest, $chart_age days ago — it is the page's only" >&2
    echo "  picture of usage over time, and it now reads as a page nobody tends" >&2
  else
    if [ "$chart_age" = "1" ]; then echo "  ends $newest, a day back"
    else echo "  ends $newest, $chart_age days back"; fi
  fi
fi

echo "→ checking how long the certificate has left"
# `|| true` on the whole pipeline: with `set -e` and `pipefail` a failed openssl
# aborts the script at the assignment, so an unreachable host killed the deploy
# without ever reaching the message written for exactly that case.
days_left=$( { 
  echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN:443" 2>/dev/null \
  | openssl x509 -noout -enddate 2>/dev/null \
  | sed 's/notAfter=//' \
  | { read -r end; python3 -c "
import sys, datetime
end = datetime.datetime.strptime(sys.argv[1].strip(), '%b %d %H:%M:%S %Y %Z')
print((end - datetime.datetime.utcnow()).days)
" "$end" 2>/dev/null; }
} || true )
if [ -z "$days_left" ]; then
  echo "  could not read the certificate's expiry" >&2; failed=1
elif [ "$days_left" -lt 20 ]; then
  echo "  the certificate expires in $days_left days and has not renewed" >&2; failed=1
else
  echo "  $days_left days left, renewal not yet due"
fi

if [ "$failed" != "0" ]; then
  echo "  deploy did not land cleanly" >&2
  echo "  the files are already live; to put the previous version back:" >&2
  echo "    $0 --rollback" >&2
  exit 1
fi
