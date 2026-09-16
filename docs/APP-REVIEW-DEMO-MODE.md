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

> Thanks for the detail in the note. You are right that there was nothing to
> look at, and this build fixes it.
>
> Softcap reports how much of a Claude or Codex subscription has been used.
> With no account added it has no data to report, which is the empty window
> you got. I cannot hand over a demo account for those two services: they
> are third party subscriptions, sharing the login breaks Anthropic's and
> OpenAI's terms, and their sign-in runs through a browser with two-factor.
>
> So this build has a demo mode instead, and it is already on the first time
> the app runs. You do not need an account, a password, a network
> connection, or to change any setting.
>
> One thing that is easy to miss: Softcap is a menu bar app. It has no Dock
> icon and opens no window when it launches. After opening it from
> Applications, look for the small ring icon in the menu bar, near the
> clock.
>
> 1. Click that ring icon. The window opens with three sample accounts
> already in it, one Codex and two Claude, each showing its five-hour and
> weekly limits with a coloured bar and a countdown to the next reset. The
> bottom line of the window reads "Demo — sample data".
>
> Please watch it for about thirty seconds. The numbers are live: the
> percentages climb, the countdowns run down, and when a limit reaches its
> reset the bar drops back and starts filling again. One of the samples sits
> at 100% with roughly forty seconds left, so a full cycle is visible almost
> straight away. That cycle is the whole point of the app.
>
> 2. Click "Settings…" at the bottom of that window, or the gear icon. Every
> screen has content on it. Accounts lists the three sample accounts and
> carries the checkbox "Show sample data" that turns this mode on and off.
> Statistics draws four weeks of usage, one line per account. Appearance,
> Notifications, Polling and launch, Services, Updates, Contribute and About
> are ordinary settings screens and show their content whether or not an
> account exists.
>
> 3. The menu bar icon itself shows the countdown for the busiest account,
> from the same samples.
>
> To switch the demo off, uncheck "Show sample data" on the Accounts screen.
> It also switches itself off for good the first time a real account is
> added.
>
> The samples are labelled as samples everywhere they appear and use
> addresses at example.com, the domain reserved for documentation. Nothing
> about them is stored or sent anywhere, and they raise no notifications.
>
> Happy to answer anything else you need.

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
