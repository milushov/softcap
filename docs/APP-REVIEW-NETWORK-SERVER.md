# Why Softcap needs `com.apple.security.network.server`

App Review's automated analysis rejects the macOS build with *"includes the
`com.apple.security.network.server` entitlement but does not appear to have
matching functionality"*. The functionality is there, and the entitlement
cannot be removed: the sandbox denies the bind without it, and signing in is
the first thing the app does.

Two texts follow. Paste the first as the reply in Resolution Center, and the
second into **App Store Connect → the version → App Review Information →
Notes**, so the next submission carries the answer with it.

---

## 1. Reply to send in Resolution Center

> Softcap does need `com.apple.security.network.server`, and here is what it
> uses it for.
>
> Softcap signs a person in to their Claude and Codex accounts with OAuth 2.0
> and PKCE, against those providers' own authorization servers. The redirect
> URI registered for those clients is a loopback address — Softcap is a native
> app, so this is the loopback-interface redirect described in RFC 8252
> (OAuth 2.0 for Native Apps), section 7.3:
>
> - Claude: `http://localhost:<ephemeral port>/callback`
> - Codex: `http://localhost:1455/auth/callback`
>
> To receive that one redirect, the app has to accept an incoming TCP
> connection on the loopback interface. It does so with `NWListener` from
> Network.framework, with `requiredLocalEndpoint` pinned to
> `.ipv4(.loopback)`, so nothing outside the machine can reach it. The
> listener starts when the person presses the sign-in button, accepts the
> single `GET /callback?code=…` the browser sends, replies with one page, and
> is cancelled as soon as the code arrives or the attempt times out. It serves
> nothing else and is not listening at any other time.
>
> The App Sandbox denies this bind without the entitlement: with
> `com.apple.security.app-sandbox` and without
> `com.apple.security.network.server`, the listener fails with POSIX error 1,
> "Operation not permitted", and sign-in cannot complete. With the entitlement
> it reaches the ready state and the redirect lands. This is not particular to
> Network.framework — a plain `socket`/`bind`/`listen` on `127.0.0.1` is denied
> the same way, so there is no implementation of the redirect receiver that
> would work without the entitlement.
>
> The relevant source file is `App/BrowserCallbackListener.swift`. The uploaded
> binary does reference these APIs — `nm -u` on it lists twelve undefined
> `NWListener` symbols, mangled as Swift symbols of Network.framework
> (`_$s7Network10NWListenerC5start5queueySo012OS_dispatch_D0C_tF` and others)
> rather than as the C entry points `nw_listener_create` or `bind`/`listen`.
> That may be why the automated analysis did not find a match.
>
> Softcap makes no outbound listening socket of any other kind, and is not a
> web, file or FTP server.
>
> To see it: open Softcap from the menu bar, choose Add Account, and pick
> Claude. The default browser opens the provider's sign-in page; approving it
> returns the browser to the loopback address, and the account appears in
> Softcap. Nothing about the flow reaches the app if the listener cannot bind.

---

## 2. Text for App Review Information → Notes

> Network entitlement: Softcap includes `com.apple.security.network.server`
> because signing in uses the OAuth 2.0 loopback redirect for native apps
> (RFC 8252 §7.3). Claude's and Codex's OAuth clients redirect to
> `http://localhost:<port>/callback`, so the app binds a TCP listener on
> 127.0.0.1 (`NWListener`, `requiredLocalEndpoint` = `.ipv4(.loopback)`, see
> `App/BrowserCallbackListener.swift`) for the duration of one sign-in and
> cancels it as soon as the authorization code arrives. The App Sandbox denies
> that bind without the entitlement — the listener fails with POSIX 1,
> "Operation not permitted" — and sign-in cannot complete. The app listens on
> no other interface, port or protocol, and is not a server of any kind.

---

## Why the entitlement was not simply removed

Removing it was measured first, not assumed. A bundle carrying
`com.apple.security.app-sandbox` and `com.apple.security.network.client`, but
not `com.apple.security.network.server`, running the same `NWListener` call as
`App/BrowserCallbackListener.swift`:

```
POSIX:
  socket+bind 127.0.0.1:0 +listen      bind() FAILED errno=1 Operation not permitted
  socket+bind 127.0.0.1:1455 +listen   bind() FAILED errno=1 Operation not permitted
  socket+bind 0.0.0.0:0 +listen        bind() FAILED errno=1 Operation not permitted
  socket+bind [::1]:0 +listen          bind() FAILED errno=1 Operation not permitted
Network.framework:
  requiredLocalEndpoint=127.0.0.1:any  FAILED POSIXErrorCode(rawValue: 1)
  requiredLocalEndpoint=127.0.0.1:1455 FAILED POSIXErrorCode(rawValue: 1)
  plain tcp, on:.any                   FAILED POSIXErrorCode(rawValue: 1)
  requiredInterfaceType=.loopback      FAILED POSIXErrorCode(rawValue: 1)
  .tcp + allowLocalEndpointReuse       FAILED POSIXErrorCode(rawValue: 1)
```

The same bundle with the entitlement added answers `OK` to all nine. The denial
is on `bind`, not on any one API, so there is no way to write the receiver that
avoids the entitlement — only a way to stop receiving.

What that costs if the entitlement goes: Claude sign-in degrades to the manual
fallback the app already has — `OAuthEndpoints.manualRedirect` shows the code
on the provider's page and the person pastes it in. Codex has no manual
redirect at all (`CodexOAuth.manualRedirectURI` is nil, and its client only
accepts port 1455), so Codex sign-in would stop working in the App Store build
entirely. That is a feature removed to satisfy an automated check that is
wrong, which is why the reply above exists instead.

Two other readings of the letter were checked and are wrong. The entitlement is
not being carried by a target that has no use for it: expanding the uploaded
package shows `network.server` on `Softcap.app` alone, and the embedded
`SoftcapWidget.appex` carries only the sandbox and the app group. And the
listener is not something the store build compiles out: the uploaded binary
holds the same twelve `NWListener` references the local build does.

`LoopbackEntitlementTests` holds the entitlements file to this, so the next
person to read the rejection letter does not delete the key before reading
this file.
