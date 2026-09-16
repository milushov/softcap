# Answering guideline 2.1(a): the reviewer saw an empty window

App Review refused 0.1.22 twice. The second letter, 16 September 2026,
submission `1a6a70ee-1471-4fa6-8c2b-3de7d3c4986b`:

> we need a populated demo account/demo mode that shows real content on all
> pages for us to review your app content and features.

The rejection is correct. Softcap reads how much of a Claude or Codex
subscription has been spent, so with no account added it has nothing to show and
says "No accounts found". A reviewer has no reason to own a paid Claude Max or
ChatGPT Plus plan, and cannot be given one: sharing those credentials is against
both providers' terms, the sign-in runs through a browser with a second factor,
and this repository does not publish account values.

So the build attached to this submission ships a demo mode, on by default until
somebody signs in. The reviewer does nothing but open the app.

Two texts follow. The first is the reply for Resolution Center. The second
replaces what is in **App Store Connect → the version → App Review Information →
Notes**, and it keeps the `network.server` answer from
`docs/APP-REVIEW-NETWORK-SERVER.md` — both questions have to travel with the
submission.

---

## 1. Reply to send in Resolution Center

> Thank you — that is a fair point, and this build fixes it.
>
> Softcap reports how much of a Claude or Codex subscription has been used. With
> no account added it has nothing to report, which is what you saw. We cannot
> hand over a demo account for those services: they are third-party
> subscriptions, sharing the credentials breaks Anthropic's and OpenAI's terms,
> and their sign-in runs through a browser with a second factor.
>
> The build attached to this submission therefore includes a demo mode, and it
> is already on when the app is first launched. No account, no password, no
> network connection and no setting are needed to review every screen.
>
> **Softcap is a menu bar app.** It has no Dock icon and opens no window of its
> own at launch. After opening it from Applications, look for a small ring icon
> in the menu bar, near the clock.
>
> 1. **The limits window.** Click that ring icon. The window opens already
>    populated with three sample accounts — one Codex and two Claude — each with
>    its five-hour and weekly limits, a coloured meter and a countdown to the
>    next reset. A line at the bottom reads "Demo — sample data".
>
>    Please watch it for about half a minute. The meters are live: the
>    percentages climb, the countdowns run down, and when a window reaches its
>    reset the bar drops and the cycle starts again. One sample account sits at
>    100% with roughly forty seconds left, so a full cycle is visible almost
>    immediately. This is the app's whole purpose, shown working.
>
> 2. **Settings.** Press the gear in that window, or "Settings…". Every screen is
>    populated:
>    - **Accounts** — the three sample accounts, and the switch labelled "Show
>      sample data" that turns this mode on and off.
>    - **Statistics** — four weeks of recorded usage, drawn as one line per
>      account.
>    - **Appearance**, **Notifications**, **Polling and launch**, **Services**,
>      **Updates**, **Contribute**, **About** — these are settings screens and
>      show their content whether or not an account exists.
>
> 3. **The menu bar itself** shows the busiest account's countdown, and follows
>    the same samples.
>
> To leave demo mode, turn off "Show sample data" on the Accounts screen. It
> switches off by itself, permanently, the first time a real account is added.
>
> The samples are clearly marked as samples everywhere they appear, and use
> addresses in `example.com`, the domain RFC 2606 reserves for documentation.
> They are not stored, not sent anywhere, and no notification is raised from
> them.

---

## 2. Text for App Review Information → Notes

> **No account is needed.** Softcap is a menu bar app — no Dock icon, no window
> at launch. Open it from Applications and click the small ring icon in the menu
> bar near the clock.
>
> Demo mode is on by default on a machine where nobody has signed in, so the
> limits window opens already populated with three sample accounts, live meters
> and running countdowns, labelled "Demo — sample data". Watching it for thirty
> seconds shows a limit filling, resetting and starting again — one sample sits
> at 100% with about forty seconds left. Settings → Accounts lists the same three
> accounts and carries the "Show sample data" switch; Settings → Statistics draws
> four weeks of history. Every other settings screen shows its content
> regardless. Nothing needs a password, a subscription or a network connection.
>
> **Network entitlement.** Softcap includes
> `com.apple.security.network.server` because signing in uses the OAuth 2.0
> loopback redirect for native apps (RFC 8252 §7.3). Claude's and Codex's OAuth
> clients redirect to `http://localhost:<port>/callback`, so the app binds a TCP
> listener on 127.0.0.1 (`NWListener`, `requiredLocalEndpoint` = `.ipv4(.loopback)`,
> see `App/BrowserCallbackListener.swift`) for the duration of one sign-in and
> cancels it as soon as the authorization code arrives. The App Sandbox denies
> that bind without the entitlement — the listener fails with POSIX 1,
> "Operation not permitted" — and sign-in cannot complete. The app listens on no
> other interface, port or protocol, and is not a server of any kind.

---

## What the mode actually is, for whoever reads this next

Not a switch built for App Review. It is on for everybody who has not signed in,
it is documented on the Accounts screen, and the same three accounts appear on
the landing page at softcap.app and in the App Store screenshots — one picture in
three places, held together by `TheDemoMatchesTheLanding`. A mode only a reviewer
can reach would be a hidden feature and rejectable under 2.3.1 on its own.

The design, and what it cost, is in `docs/DECISIONS.md` under
*2026-09-16 — App Review is answered about an empty window with a mode, not an
account*. The data and the clock are `App/DemoData.swift`.

Two things about the demo will look odd to somebody reading the code for the
first time, and both are deliberate:

- **The countdown races.** The demo clock runs at sixty times real time, and the
  label is stamped from the demo remainder, so "41m" loses a minute every second.
  Slowing it to real time means a bar that fills to the top while the clock beside
  it still says two hours — a window contradicting itself.
- **`Preferences.demoMode` is `Bool?`, not `Bool`.** Every installation of 0.1.22
  stored preferences with no such key. A `Bool` defaulting to true would have
  shown all of them three invented accounts on the morning they updated; `nil`
  resolves to "on" only after a finished poll has found no accounts.
