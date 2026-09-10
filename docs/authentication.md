# Browser authentication

Softcap supports separate browser grants for Claude Code and OpenAI Codex.
Choose the provider from **Add account…** in Accounts or the menu bar context
menu. Codex signs into ChatGPT subscription access, not OpenAI API billing.
A saved account can be reconnected using its **Sign in…** button.

## Ownership and dependencies

- `ProviderKit` owns `HTTPClient`, PKCE, callback parsing, token results and the
  `BrowserAuthenticating` and `AccountTokenSource` contracts. The HTTP transport
  remains the only request builder. Updates and diagnostics use it directly.
- Each provider supplies authorization parameters, redirect policy, token
  exchange and identity lookup. Claude reads its profile endpoint; Codex reads
  identity claims from the ID token returned over HTTPS. Decoded JWT claims are
  metadata, not an independent identity verification mechanism.
- `LoginController` owns one attempt, opens the browser and drives the loopback
  listener. Cancelled attempts cannot open a browser, publish success or save a
  delayed exchange result. A timeout includes binding, browser interaction and
  code exchange. The listener binds only to loopback and bounds incoming headers.
- `CredentialStore` owns accounts in the existing `StatusChecker-accounts`
  keychain item. IDs include the provider namespace, so equal handles cannot
  collide. Legacy Claude records keep their format and decode without migration.
  The initial access token is saved with its expiry. Refreshes are coalesced per
  account, persisted after rotation and dispatched to the matching provider.
  Responses from a superseded grant cannot overwrite a subsequent sign-in.

Claude's existing CLI import remains read-only while that account is active in
the CLI. Codex CLI credentials are never imported for refresh and its `auth.json`
is never written. Browser accounts use grants issued to Softcap's own attempt.

## Codex protocol compatibility

The browser uses `auth.openai.com/oauth/authorize` and exchanges the code at
`auth.openai.com/oauth/token` with an encoded form body, the public Codex client
identifier, PKCE S256 and `openid profile email offline_access`. The callback is
`http://localhost:1455/auth/callback`. A busy port produces a retryable error;
Softcap does not cancel another application's listener or invent a manual redirect.
Claude retains its provider-specific manual code fallback.

The callback parser checks the request method, exact path, unique code/state
parameters and matching state, including on error replies. Requests unrelated to
the attempt leave it running. OAuth codes, verifiers, response bodies and tokens
are not logged or included in diagnostics.

The browser flow and default loopback port are described in
[OpenAI authentication documentation](https://learn.chatgpt.com/docs/auth).
[OpenAI App Server documentation](https://learn.chatgpt.com/docs/app-server)
also describes browser login and a separate account rate-limit read operation.
The public client constants, form exchange and usage response fields were checked
against the locally installed Codex CLI on 2026-09-10. These first-party client
endpoints are not a versioned public integration API: upstream changes can require
an adapter update. Softcap implements the flow directly and does not require a
Codex executable or launch a model session.

## Usage sources

`CodexLiveUsageProvider` reads `chatgpt.com/backend-api/wham/usage` with the saved
account's bearer token and `ChatGPT-Account-Id`. It maps primary and secondary
windows to the same session/weekly models used elsewhere. Missing or malformed
windows are failures, never zero usage. A 401 invalidates that specific cached
access token and retries once; network and server failures preserve the refresh
grant. Explicit terminal refresh errors require a new sign-in.

`CodexUsageProvider` continues reading local session files. Stored or hidden IDs
are excluded from local discovery, preventing duplicate rows or a hidden account
returning through a different source. A saved grant failure remains visible and
does not silently substitute another account's local readings. Local history
import and FSEvents watching are retained.

Saved Codex accounts also participate in iOS polling. Local file discovery stays
on macOS. As with existing Claude accounts, refresh coalescing covers one store
instance; it does not provide a distributed lock across devices sharing iCloud
Keychain.

## Verification

Run `make test` for provider, parsing, persistence, namespace and rotation tests.
Run `make test-auth` for the AppKit controller and real
loopback listener, using fake accounts and a fake browser. The latter checks
cancellation, timeout, occupied ports, stale completions and a complete local
callback without reading user credentials or contacting a provider.

Build both the `Softcap` and `SoftcapiOS` schemes after changing shared contracts.
A complete real OpenAI/Claude consent flow still needs a person to sign in in
the browser; offline tests cannot verify server-side acceptance or plan access.
