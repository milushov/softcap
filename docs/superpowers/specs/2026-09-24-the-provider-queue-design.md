# The provider queue, ordered by what each service will let us read

Three services are watched. The question this answers is which is fourth, and
the ordering rule is not popularity: it is how well a service integrates, which
means all three of what a service will let a third party read, what shape the
reading arrives in, and what credential it needs.

Measured that way the order came out different from the one anybody would guess
from a list of market shares, and different from a first draft of this document.

## The field

**Cursor — closed.** The official API is team scoped; an individual cannot make
a key. The editor's backend wants a machine-derived `x-cursor-checksum`
alongside `x-cursor-client-type: ide`, which is reproducing an anti-abuse
control rather than presenting as a published client. The third route is the
web session cookie, which this app has refused since it stopped reading the
Claude Code keychain item. `docs/DECISIONS.md` carries the entry.

**Gemini — best data, blocked outside.** `v1internal:retrieveUserQuota` returns
a `remainingFraction` and a `resetTime` per model, which is exactly what
`LimitWindow` wants, and the browser sign-in already here needs no second
shape. It waits on an OAuth client of our own: the Code Assist scope is
sensitive in Google's classification, so the client needs verification, and
without it the consent screen warns and the client is capped at a hundred
users. Registering and submitting it is the author's to do.

**OpenRouter — best credential, wrong shape.** The cleanest sign-in any service
offers: documented public OAuth PKCE, no client registration, no secret, and
loopback on any port explicitly blessed for local-first apps. It would be the
first provider here that is a public API rather than a first-party endpoint.

And it does not fit. `GET /api/v1/key` returns `limit`, `limit_remaining` and
`limit_reset` — all `null` unless the person has capped that key, which most do
not — beside `usage_daily`, `usage_weekly` and `usage_monthly`, which are
credits spent. This app draws a proportion of a limit. For a typical OpenRouter
account there is no limit, so there is no proportion, and the row would be a
name with no bars — the rare case Copilot's unlimited plan produces, made the
normal one.

Showing it properly would mean the app learning to display spend as well as
fullness. That is a change to what the product is and is not made here.

**Amp — nothing to call.** Balance is read by `amp usage` at a terminal; no HTTP
endpoint is documented. Reading it would mean running somebody else's binary,
which this app does not do for Codex and will not start doing here.

**Windsurf — nothing found.** Quotas were reworked into daily and weekly
allowances in March 2026 and no usage API is documented for an individual plan.

**Z.ai GLM Coding Plan — fourth.** Below.

## Z.ai: the reading

`GET https://api.z.ai/api/monitor/usage/quota/limit`, with the coding-plan key
in `Authorization` and **no `Bearer` prefix** — the prefix is refused with 401.
The China platform answers the same path at `open.bigmodel.cn`, which is a later
question and not this one.

    {"code":200,"success":true,"data":{"level":"lite","limits":[
      {"type":"CREDIT_LIMIT","unit":3,"number":5,"usage":2000,
       "currentValue":251,"remaining":1748,"percentage":12,
       "nextResetTime":1790256683169},
      {"type":"CREDIT_LIMIT","unit":6,"number":1,"usage":10000,
       "currentValue":251,"remaining":9748,"percentage":2,
       "nextResetTime":1790791834975}]}}

`usage` is the allowance and `currentValue` is what has gone; the names are the
wrong way round from what they look like, and reading them the obvious way
produces a row that is wrong and plausible. `percentage` is the used share,
floored. `nextResetTime` is epoch milliseconds.

`unit` identifies the window: **3 is the five-hour window, 6 is the weekly one**.
Those are `session` and `weekly` — the two identifiers this app already has.
Nothing new is named, no catalogue gains a key, and the period column keeps the
width it has. No other service has fitted this cleanly.

**Read `unit`, never `type`.** The field says `CREDIT_LIMIT` today and said
`TIME_LIMIT` and `TOKENS_LIMIT` until recently. Every tool that keyed on `type`
dropped the new entries silently and showed zeros — the exact failure this
project treats as worse than showing nothing, and it happened to several of them
in the same week. Keying on `unit` survives the change in both directions, and
an entry whose unit is unknown is skipped rather than guessed at.

A `limits` array that is absent, not an array, or holds no window this app knows
is `malformed`. It is never zero usage: the whole point of the paragraph above
is that somebody else's parser turned a schema change into a confident nought.

## Z.ai: the credential, and why a pasted key is admissible

The coding plan issues a key, and there is no OAuth. So the person pastes it,
which no provider here has done before and which the rules appear to forbid.

They do not, once the reason behind them is read. "No credential is imported
from any CLI" exists because **refreshing rotates**: spending a refresh token
copied from Claude Code retires the CLI's copy and signs it out, which is an app
for watching limits breaking the tool it watches. That is the harm, and it is
specific to a credential that rotates on use.

A coding-plan key is static. Reading a quota with it invalidates nothing,
rotates nothing and signs nothing out; the person's own editor goes on using the
same key, unaffected. And a key typed into a field is given, not imported — no
file of anybody's is read, which is the other half of the rule and stays whole.

So the machinery is the one Copilot already needed: `rotatesCredentials` is
false, the store serves the stored credential as it is, and nothing is ever sent
to a refresher. `TokenOrigin` gains a third case rather than stretching
`ownGrant` to cover something that is not a grant of ours.

## What the row is called — settled, 25 September

This endpoint returns a plan level and nothing else, where every other service
answers who the account belongs to: Claude a profile, Codex an ID token, Copilot
`api.github.com/user`. Two answers were on the table — ask the person to name
the account beside the key, or take the plan level — and searching for a third
found none: there is no identity endpoint, and the key management the API
documents is a web page.

**The plan level was chosen**, and the row reads `Lite`, `Pro` or `Max`. The
cost is two accounts on one plan reading alike, with no rename anywhere in the
app to recover with. The identifier is a truncated SHA-256 of the key rather
than anything the service supplies, so at least the same key lands on the same
row instead of leaving two nobody can tell apart *or* remove.
`docs/DECISIONS.md` carries the whole of it.

## Where the queue stands

Claude, Codex, Copilot and the GLM Coding Plan are implemented. Copilot and GLM
have never been answered by a real subscription, which is the standing risk of
this queue and the reason neither is claimed as supported on the site.

Nothing is left in it that can be finished from here:

- **OpenRouter** needs the app to show spend as well as fullness, which is a
  change to what the product is.
- **Gemini** needs an OAuth client of our own, registered and put through
  Google's verification for a sensitive scope.
- **Cursor** is closed on the terms above.

Both remaining names wait on a decision or an account that only the author has.
