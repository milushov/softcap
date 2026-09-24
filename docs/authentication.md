# Browser authentication

Softcap supports separate grants for Claude Code, OpenAI Codex and GitHub
Copilot. Choose the provider from **Add account…** in Accounts or the menu bar
context menu. Codex signs into ChatGPT subscription access, not OpenAI API
billing. A saved account can be reconnected using its **Sign in…** button.

There are two shapes of sign-in. Claude and Codex catch a redirect on a loopback
port; Copilot carries a code to a page. Which one a provider uses is named by
`LoginController.deviceProviders`, and only the controller and the screen know
the difference — everything downstream receives the same `AuthenticatedAccount`.

## Ownership and dependencies

- `ProviderKit` owns `HTTPClient`, PKCE, callback parsing, token results and the
  `BrowserAuthenticating` and `AccountTokenSource` contracts. The HTTP transport
  remains the only request builder. Updates and diagnostics use it directly.
- Each provider supplies authorization parameters, redirect policy, token
  exchange and identity lookup. Claude reads its profile endpoint; Codex reads
  identity claims from the ID token returned over HTTPS. Decoded JWT claims are
  metadata, not an independent identity verification mechanism.
- `DeviceCodeAuthenticating` is the second shape: `requestCode()` asks for a
  code and the page to type it into, and `poll(_:)` takes one look at whether
  the person has finished. It shares no ancestor with `BrowserAuthenticating`
  because it shares no step. The loop, the deadline and the screen belong to
  `LoginController`, as the browser and the listener already do; both shapes end
  at the same `adopt`, so the success notice, the counter and the callback have
  one definition rather than two that can drift.
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
- Whether there is anything to rotate is the service's to say, through
  `ProviderID.rotatesCredentials`. For a rotating service an account holding no
  refresh token is a spent grant and is refused, which is what stops a dead
  account being retried on every poll forever. For a static one it is the normal
  resting state of a working account, and the stored token is served as it is. A
  single refused request does not discard a static token either: it is not a
  cached copy of anything, and throwing it away over one status would destroy
  the account rather than refresh it.

No credential is imported from any CLI. `SystemKeychain` reads and writes one
item, `StatusChecker-accounts`, and there is no code path to any other — which is
why nothing here can raise the keychain's access dialog. A record carried over
from an older build may hold a token copied from Claude Code; `accessToken(for:)`
refuses to spend it, because the server rotates a refresh token on use and that
would sign the CLI out. Those records report `needsLogin` until a browser grant
replaces them.

## Codex protocol compatibility

The browser uses `auth.openai.com/oauth/authorize` and exchanges the code at
`auth.openai.com/oauth/token` with an encoded form body, the public Codex client
identifier, PKCE S256 and `openid profile email offline_access`. The callback is
`http://localhost:1455/auth/callback`. A busy port produces a retryable error;
Softcap does not cancel another application's listener or invent a manual redirect.
Claude retains its provider-specific manual code fallback.

## Copilot protocol compatibility

The device grant follows RFC 8628: `github.com/login/device/code` for the code,
`github.com/login/oauth/access_token` with
`grant_type=urn:ietf:params:oauth:grant-type:device_code` to redeem it, both
form-encoded and both asked for `Accept: application/json` — without that header
the refusals, which carry the whole state machine, come back as query strings.
The whole machine arrives with a 200 and a word in `error`, so the status alone
decides nothing: `authorization_pending` waits, `slow_down` raises the interval
for the rest of the attempt, `access_denied` and `expired_token` end it, and
anything else asks for a new sign-in rather than looping.

The client identifier is the published editor client. A public client has no
secret, which is why the device grant is used at all: GitHub requires one at the
exchange for the authorization-code flow and does not take PKCE in its place.

Identity comes from `api.github.com/user`; the account is filed under the
numeric identifier, because a login can be changed by its owner and the number
cannot, and the login is what the row shows.

The token a public client receives does not expire and carries no refresh token.
GitHub can be configured to expire them, and when it is the reply carries both —
`GitHubTokenRefresher` is registered for that case, so the behaviour follows the
reply rather than an assumption about it.

Usage is `api.github.com/copilot_internal/user`, read-only, with no model
request of any kind. It returns a plan and a `quota_snapshots` map;
`CopilotQuotaResponse` reads the premium allowance from it and leaves chat and
completions alone — see the decision log for why one window and not three. An
unlimited allowance is dropped rather than drawn at zero, and a reply whose
quota map is absent or unreadable is `malformed`, never zero usage.

These are first-party editor endpoints, not a versioned public integration API:
the same footing as the two above, and the same obligation when one moves. **They
have not been checked against a live Copilot subscription.** Every constant is
from published documentation and every test reply is a recording, which proves
the adapter reads what it was told to expect and not that the service sends it.

## Returning to Softcap

For the two providers that use it, the loopback response waits until the grant
is exchanged and the account is saved. Only then does its page try `window.close()`. The app
independently opens or restores Settings, selects Accounts and shows a dismissible
success banner with the provider and account name. This also works when settings
were closed or another section was selected during sign-in. The banner stays
above the scrolling account list until dismissed or another sign-in starts.
Previously hidden accounts and providers are made visible before refreshing usage;
window activation does not wait for that refresh.

Closing the tab is best effort: browsers can refuse script-driven closing of a
tab opened by another app. In that case the localized page confirms completion
and says the tab can be closed. Native activation does not require JavaScript,
browser automation permissions or a custom URL scheme. See
[the browser closing restrictions](https://developer.mozilla.org/en-US/docs/Web/API/Window/close).
Claude's manual code fallback shows the same in-app completion; its remote page
is outside Softcap's control and cannot be closed by the loopback response.

Failed, cancelled or timed-out attempts never run the close script or trigger
success activation. The listener's header deadline ends once a complete request
is handed to the controller; the attempt timeout bounds the browser interaction
and exchange. Once the keychain write starts, the UI shows **Saving account…**,
disables cancellation and waits for its actual result. A system keychain write
cannot be rolled back by cancelling a task, so reporting a timeout at that point
would let a supposedly failed attempt save an account after a retry had started.
The response is not cached, sends no referrer and removes the callback query from
the address bar when browser scripting permits it.

## Callback validation

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

The iOS poller supports every saved account the Mac wrote — Claude, Codex and
Copilot alike — but the phone has no sign-in of any kind, of either shape, and
no working account sync from the Mac. `SystemKeychain` does not
set `kSecAttrSynchronizable`, and the targets do not configure a shared Keychain
access group. Items remain local: Apple requires
[explicit opt-in for Keychain synchronization](https://developer.apple.com/documentation/security/ksecattrsynchronizable).
A fresh iOS install therefore has no accounts. Refresh coalescing covers one
credential-store instance.

## When the saved list cannot be read

The keychain binds access to the code signature that created the item, not to
the bundle identifier. A build signed ad-hoc is a different application every
time it is built, so an update can arrive unable to read the accounts the
previous one saved: `SecItemCopyMatching` returns `-25293` while the read
refuses the access dialog, and `load()` records the list as present but
unreadable. Nothing may then be written over it — the item is the only copy of
every account's refresh token — so a browser sign-in completes, the code is
exchanged, the profile is read, and `addLoggedInAccount` throws
`WouldOverwriteUnreadableAccounts`.

`CredentialStore.whyUnreadable()` distinguishes the two ways this happens.
`keychainRefusedThisBuild` means the item did not open; nothing is lost, and
`openWithPermission()` reads it again with the keychain's question allowed, off
the actor, reached only from the Accounts screen's **Open saved accounts**
button. `contentNotUnderstood` means it opened and the contents did not decode;
there is nothing to ask anybody, and only `startOver()` moves on from it.

`startOver()` replaces the item rather than writing into it. A write succeeds
even from a build the item does not belong to and leaves the old access control
in place, which would store new accounts somewhere unreadable. `SecItemDelete`
on the query refuses with `-25244`; the item's reference decrypts nothing, so
`SecKeychainItemDelete` on that reference succeeds and the replacement belongs
to the running build. It throws `NothingToStartOverFrom` unless the list is
actually unreadable, because it destroys every refresh token the item held.

`keychainRefusedThisBuild` is claimed only for `errSecAuthFailed` and
`errSecInteractionNotAllowed` — the two statuses that mean the item's access
check turned this caller away. Any other status is `keychainDidNotOpen`, which
says the keychain did not answer and nothing more: a locked keychain reported as
a signature mismatch would state a cause beside a button that deletes tokens.

Launch never raises the dialog. It writes the keychain's status to the unified
log under the `poll` category — the app model's own logger — and leaves the
decision to a person on a screen they are looking at. Nothing about it is sent
to the diagnostics collector.

## Verification

Run `make test` for provider, parsing, persistence, namespace and rotation
tests. `CopilotProviderTests` covers the quota reading and the device flow's
state machine against recorded replies; `AStaticGrantIsServedAsItIs` holds both
halves of the rotation rule in one file, so narrowing it further, or widening it
back, fails there.
Run `make test-auth` for the AppKit controller and real
loopback listener, using fake accounts and a fake browser. The latter checks
both browser providers, manual fallback, cancellation, timeout, occupied ports,
stale completions, cancellation and timeout during delayed persistence, failed
saves, and responses held beyond the header deadline. `DeviceSignIn` covers the
other shape against a scripted service: the code reaching the screen, waiting
then granting, being told to slow down, refusal, a stale code, cancellation
stopping the loop, a browser that will not open, and a save that fails. JavaScriptCore runs the completion-page script, including blocked browser
APIs. These tests do not read user credentials or contact a provider.

Build both the `Softcap` and `SoftcapiOS` schemes after changing shared contracts.
A complete real consent flow still needs a person to sign in — in the browser
for Claude and Codex, on the device page for Copilot. Offline tests cannot
verify server-side acceptance or plan access, and for Copilot nobody has done it
yet: see the compatibility note above.
