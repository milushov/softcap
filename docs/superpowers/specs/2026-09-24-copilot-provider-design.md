# A third service, and what it costs to stop being a pair

Softcap watches two services. `ProviderID` has named five since the beginning —
`claude`, `codex`, `cursor`, `copilot`, `gemini` — and the Services screen lists
the last three under **Later**. That list is a promise made in the interface,
and this is the first of the three to be kept.

Copilot goes first, alone. The other two are not deferred for lack of interest:
each needs something this one does not. Cursor reports what has been spent of an
included budget rather than how full a window is, which the limit model here
cannot express without being widened. Gemini has no grant a third party may ask
for without registering and verifying an application with Google first, and that
wait is external. Copilot needs neither, so it is the one that can be finished.

Shipping one service also answers a question two services never asked: whether
anything here is written for a pair rather than for a set. The answer, below, is
that two things are.

## What the service gives us

A sign-in yields a token. `api.github.com/copilot_internal/user` returns, for
the signed-in person, a plan name and a `quota_snapshots` map keyed by the kind
of allowance: `chat`, `completions`, `premium_interactions`. Each entry carries
`entitlement`, `remaining`, `percent_remaining`, `unlimited`,
`overage_permitted`, and the map is accompanied by the date the allowance next
resets.

This is a first-party endpoint belonging to the editor integrations, not a
versioned public API — the same footing as the two endpoints already read, and
`docs/authentication.md` already states that boundary and what it obliges us to
do when it moves.

## Sign-in is a second shape, not a second copy

Both existing services sign in the same way: open a browser, catch the reply on
a loopback port, exchange the code with PKCE. GitHub cannot be signed into that
way. Its authorization-code flow requires a client secret at the exchange, and a
desktop application that shipped one would be shipping it to everybody; PKCE is
not offered as a substitute for that client kind.

What it does offer is the device grant: ask for a code, show the person a short
string, send them to a page to type it, poll until they have. No secret, no
redirect, no listening socket. So Softcap gains a second shape of sign-in:

    DeviceCodeAuthenticating
        requestCode()  -> DeviceCodeGrant   (user code, verification page, poll interval, deadline)
        poll(grant)    -> pending | slowDown(interval) | granted(account)

One look, not the whole loop. The attempt belongs to `LoginController` — it is
what can be cancelled, what holds the deadline and what has a screen to put the
code on — which is the same division `BrowserAuthenticating` already has, where
the provider says what to ask for and the app owns the browser.

`BrowserAuthenticating` is untouched. The two protocols do not share a base:
they have no step in common — one binds a port and parses a request line, the
other polls an endpoint on a schedule the server dictates — and a shared
ancestor would exist only to have one.

The client identifier is the editor's published one, which is the stance already
taken for both other services: Claude's constants were read from Claude Code and
Codex's from the Codex CLI, and each is recorded as a public client in its own
source file. Nothing secret is committed, because there is nothing secret to
commit.

## Where it does not fit, and what gives way

Two places in this codebase are written for exactly two services.

**The store assumes every grant rotates.** `CredentialStore.accessToken(for:)`
ends at

    guard let refresh = accounts[index].refreshToken else { ... needsLogin }

because for Anthropic and OpenAI a grant without a refresh token is a grant that
has been spent. A device grant for a public GitHub client is the opposite: it
does not expire and there is no refresh token to hold, so an account saved from
one would report "sign in again" on every poll, forever, while holding a token
that works.

So the store learns that rotation is a property of the service. A provider
marked as not rotating serves its stored token directly when it has no refresh
token; every other provider keeps today's guard exactly as it is, because that
guard is what stops a spent Claude grant from being retried until the end of
time. GitHub can be configured to expire tokens, so the refreshing path stays
registered too — if a refresh token does come back it is saved and spent
normally. The behaviour follows the reply, not an assumption about it.

**The limit windows are a closed pair.** `session` and `weekly` are the only
identifiers the two services produce. Copilot's allowances are neither: they
are monthly, and the reply carries three at once — premium requests, chat and
completions.

The rest of the interface turns out not to care that a third kind exists.
`windowTitle` falls back to the identifier, the threshold notifications fall
back to unnamed wording, and `headlineWindow(for:)` falls back to the busiest
window. Every one of those fallbacks was written for a window kind nobody had
met yet, and this is that window kind arriving. What they need is not new
branches but a name, in all ten catalogues, so the row reads a word and the
notification says which limit reset.

What the interface *is* built for is one window or two. The period column is a
single width shared by every row on screen, so that a glance can read down it;
the full row fixes it at 34 points; the compact layout is two bars; the
"Primary window" setting offers the five-hour or the weekly. A third bar
labelled with a word longer than `5h` or `week` widens every Claude and Codex
row on screen for a service those rows are not from.

So this reports one allowance: premium requests, the one that binds on every
plan and the reason anybody watches Copilot at all. It is named for its period
— `month` — the way the other two services name theirs, which keeps the row's
vocabulary one thing rather than two. Chat and completions are unlimited on
every paid plan; on the free plan they are real, and are what this costs.

`peekChoice` needs nothing. A one-window row resolves to the same window under
either setting, so `hasAnotherPeriod` is already false and the control that
would flip it never appears. This spec said otherwise before the code was
written, and the code is what settled it.

## What a row says

Percent is used, not remaining — the app's convention everywhere — and is
computed from `entitlement` and `remaining`, which are exact, falling back to
`percent_remaining` when they are absent. Overage lets the count run past the
entitlement, so the division is clamped to the bar's ends.

An account whose premium allowance is unlimited has no windows. That is a row
with a name and a plan and no bars, and it is true. It is not a failure: the
existing rule that a missing window is a failure rather than zero usage is
about a window the service reported and we could not read, which is a different
thing from a service reporting that there is no limit to show. A
`quota_snapshots` that is absent or unparseable stays `malformed`, as before.

## Testing

The provider is tested against recorded replies, as both others are: a paid plan
with one limited allowance, a free plan with three, an all-unlimited plan, a
reply missing the quota map, a 401. The device flow is tested against a fake
transport for the whole sequence — pending, slow down, denied, expired, granted
— without a network.

The store gets the test the change is actually about: a non-rotating account
with no refresh token serves its token, and a Claude account with no refresh
token still asks for a sign-in. Those two assertions in one file are the point
of the change and the guard against it being widened later by accident.

None of this is a substitute for one live sign-in. Every constant here comes
from published documentation and every reply is a recording, so the tests prove
the adapter reads what it was told to expect — not that the service sends it.
The page's own answer about which providers are supported sets the standard:
a provider that has not been checked against a live account would quietly show
zero, which is worse than nothing. So the claims on the site stay as they are
until somebody signs in with a real Copilot subscription and the numbers match
what GitHub shows them.

## What this does not do

No Cursor and no Gemini. No import of any credential from any CLI — that rule is
unchanged and this service is no exception to it. The iOS target gains nothing:
it has no sign-in of any kind, and a device grant is still a sign-in.
