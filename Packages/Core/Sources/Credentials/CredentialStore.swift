import Foundation
import ProviderKit
import ClaudeProvider

/// The account list and token vending.
///
/// The account currently active in the CLI is read-only: refreshing may rotate
/// the token on the server side, leaving the CLI with a stale one and signing it
/// out. Inactive accounts have no such tie to the CLI, so they are refreshed
/// from their saved copy — which is what makes all subscriptions visible at once.
public actor CredentialStore: ClaudeTokenSource, AccountTokenSource {
    public static let cliService = "Claude Code-credentials"
    /// Deliberately still the old name after the rename to Softcap. Keychain
    /// access is bound to the code signature, not to the bundle identifier, so
    /// the string can stay — and accounts gathered from the CLI are the one
    /// thing here that does not come back by itself.
    public static let ownService = "StatusChecker-accounts"

    private let keychain: any KeychainAccess
    private let refreshers: [ProviderID: any TokenRefreshing]
    /// How long to hold what was read from the keychain. Enough for one poll;
    /// the CLI token does not expire in that time — it lives about eight hours.
    /// Tests pass zero so they can check reads without the delay.
    private let cacheWindow: TimeInterval
    private var accounts: [StoredAccount] = []
    private var cliCache: (oauth: [String: Any], readAt: Date)?

    /// The refresh under way for each account, so a second caller arriving
    /// while the request is out joins it instead of spending the same
    /// single-use token again.
    ///
    /// An actor is reentrant at every `await`: while one caller waits on the
    /// network, another walks in. Without this map the second one refreshed
    /// too — with a token the first spend had already rotated away — and the
    /// server's `invalid_grant` read as an account that needs signing in.
    private struct RefreshFlight {
        let id = UUID()
        let spending: String
        let task: Task<String, any Error>
    }
    private var refreshInFlight: [String: RefreshFlight] = [:]

    /// Refresh this long before the server's own deadline.
    ///
    /// Without a margin a token could pass the check with a second to live and
    /// expire inside the request it was fetched for — a failure that would
    /// appear at random and never in a test.
    private static let expiryMargin: TimeInterval = 60

    /// Reading the clock, so a test can move it.
    private let now: @Sendable () -> Date

    public init(
        keychain: any KeychainAccess,
        refresher: any TokenRefreshing,
        codexRefresher: any TokenRefreshing = OpenAITokenRefresher(),
        cacheWindow: TimeInterval = 10,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.keychain = keychain
        self.refreshers = [.claude: refresher, .codex: codexRefresher]
        self.cacheWindow = cacheWindow
        self.now = now
    }

    /// Set when the item was read and could not be understood — as opposed to
    /// there being nothing stored yet. The difference decides whether it is safe
    /// to write.
    private var storedButUnreadable = false

    /// Reads the saved list. Called once, right after construction.
    public func load() async {
        guard let data = try? await keychain.read(service: Self.ownService,
                                                  promptIfNeeded: promptAllowed)
        else { return }
        guard let stored = try? JSONDecoder().decode([StoredAccount].self, from: data) else {
            // Something is in the item and this build cannot read it. The list
            // stays empty so the interface says so — but nothing may be written
            // over it, because what is in there is the only copy of the refresh
            // tokens for every account not currently active in the CLI.
            storedButUnreadable = true
            return
        }
        accounts = stored
    }

    /// Whether anything still needs the keychain item Claude Code owns.
    ///
    /// Opening that item is what raises the access dialog, and the grant it asks
    /// for does not last: Claude Code rewrites the item whenever it refreshes,
    /// and the access list goes with it. So the read is worth making only while
    /// something depends on it — an account living off a copy taken from the
    /// CLI, or an empty list with the CLI's own account still to be discovered.
    /// That first case is the one prompt worth spending, at setup.
    ///
    /// Once every account carries a grant of this app's own, the answer is
    /// `false` for good and the item is never opened again.
    public func dependsOnCLI() -> Bool {
        accounts.isEmpty || accounts.contains { $0.provider == .claude && !$0.isOwnGrant }
    }

    public func knownRefs() -> [AccountRef] {
        accounts.map {
            AccountRef(id: $0.id, provider: $0.provider, handle: $0.handle,
                       lastKnownName: $0.displayName)
        }
    }

    /// Reconciles with whatever the CLI holds now: adds the account if it is
    /// new and renews the copy of its refresh token.
    ///
    /// The copy must be taken on every poll. Otherwise, once the user moves to
    /// another account, this one's token is overwritten in the keychain and the
    /// account disappears from the list for good.
    public func syncWithCLI(profileUUID: String, displayName: String) async throws {
        let refresh = try? await currentCLIRefreshToken()

        if let index = accounts.firstIndex(where: { $0.id == "claude/\(profileUUID)" }) {
            accounts[index].displayName = displayName
            // An own grant is never replaced by a copy of the CLI's token.
            //
            // The copy exists so that an account stays visible after `/login`
            // moves on to another one; an account holding its own grant does not
            // need it. Taking it anyway would leave that account holding Claude
            // Code's own refresh token while still marked independent, and the
            // next poll would send that token to be rotated — signing the CLI
            // out. An app for watching limits must not break the tool it
            // watches.
            if let refresh, !accounts[index].isOwnGrant {
                accounts[index].refreshToken = refresh
            }
        } else {
            accounts.append(StoredAccount(
                id: "claude/\(profileUUID)", handle: profileUUID,
                displayName: displayName, refreshToken: refresh,
                tokenOrigin: .copiedFromCLI
            ))
        }
        try await persist()
    }

    public func accessToken(for handle: String) async throws -> String {
        try await accessToken(for: AccountRef(id: "claude/\(handle)", provider: .claude, handle: handle))
    }

    public func accessToken(for ref: AccountRef) async throws -> String {
        // A change the keychain refused earlier is retried before anything
        // else. Every poll passes through here, so a keychain that has come
        // back gets the only copy of a rotated credential at the first
        // opportunity rather than at the next rotation.
        if unsavedChanges { await persistRemembering() }

        guard let index = accounts.firstIndex(where: { $0.id == ref.id && $0.provider == ref.provider }) else {
            throw ProviderFailure(kind: .needsLogin, diagnostic: "account not found")
        }

        // An own grant is this app's own credential. Refreshing it rotates our
        // token and nobody else's, so there is nothing to learn from the CLI's
        // item and no reason to open it — and opening it is the entire cost.
        // macOS checks a foreign item against its access list on every read, and
        // the grant that check looks for does not survive the item's owner
        // rewriting it, which Claude Code does on every refresh. This branch is
        // the one that never raises a dialog, today or in eight hours.
        // Note the shape: an own grant leaves here whatever happens to it. Written
        // as "own grant *and* a token", a grant the server had finished with fell
        // out of the branch and down into the CLI path below — opening the
        // foreign item again, every poll, for an account that only a sign-in can
        // fix, while `dependsOnCLI()` went on reporting there was no reason to
        // look. The claim and the behaviour have to agree.
        if accounts[index].isOwnGrant || accounts[index].provider != .claude {
            guard let refresh = accounts[index].refreshToken else {
                throw ProviderFailure(
                    kind: .needsLogin, diagnostic: "own grant spent; sign in"
                )
            }
            return try await refreshing(at: index, with: refresh)
        }

        // Everything below is a token copied from the CLI, so the CLI's item is
        // still the authority on which account is active there.
        do {
            let active = try await currentCLIAccountToken()
            if active.handle == ref.handle { return active.token }
        } catch let failure as ProviderFailure where failure.kind == .needsPermission {
            // The CLI's item is one item, so a refusal is refused for everybody.
            // It must not condemn an account holding a working copy of its own —
            // three accounts that had been polling happily once failed together
            // the moment this refusal started being detected properly.
            //
            // Nor is it the answer for an account with no copy any more. That
            // used to report "allow keychain access", which is advice that
            // cannot hold: the grant is erased the next time Claude Code
            // refreshes. Such an account falls through to the sign-in below,
            // which gives it a grant of its own and ends the matter.
        } catch {
            // Any other reason is fine here: the account is simply not the
            // active one, and its own copy is next.
        }

        // The CLI read awaited another actor. The list may have changed there.
        guard let index = accounts.firstIndex(where: { $0.id == ref.id }),
              let refresh = accounts[index].refreshToken else {
            throw ProviderFailure(
                kind: .needsLogin, diagnostic: "no usable credential; sign in"
            )
        }
        return try await refreshing(at: index, with: refresh)
    }

    /// Serves the held token while it is good, and otherwise trades the
    /// refresh token for a new one — through one request at a time per account.
    private func refreshing(at index: Int, with refresh: String) async throws -> String {
        // A token already in hand and not yet near its deadline serves this poll
        // as well as a new one would. Every refresh spends the refresh token —
        // the server rotates it on use — so a refresh made for no reason is a
        // rotation made for no reason, and each rotation is a chance for the
        // reply to be lost and the account left holding a retired credential.
        if let held = accounts[index].accessToken,
           let until = accounts[index].accessGoodUntil, until > now() {
            return held
        }

        // One request per account, however many callers want its token. This
        // check, the insertion below it and the held-token check above run as
        // one synchronous stretch on the actor, which is what makes them one
        // decision: no second caller can slip in between them.
        let id = accounts[index].id
        if let running = refreshInFlight[id], running.spending == refresh {
            return try await running.task.value
        }
        let provider = accounts[index].provider
        let run = RefreshFlight(spending: refresh, task: Task {
            try await performRefresh(id: id, provider: provider, spending: refresh)
        })
        refreshInFlight[id] = run
        defer {
            if refreshInFlight[id]?.id == run.id { refreshInFlight[id] = nil }
        }
        return try await run.task.value
    }

    /// Spends the refresh token and writes down everything the reply granted.
    ///
    /// The account is found by handle again after the network call rather than
    /// addressed by the position it held before it: the list can change while
    /// the request is out, and an index kept across that wait once crashed on
    /// a list a `forget` had emptied in the meantime.
    private func performRefresh(id: String, provider: ProviderID, spending refresh: String) async throws -> String {
        let fresh: RefreshedTokens
        do {
            guard let service = refreshers[provider] else {
                throw ProviderFailure(kind: .needsLogin, diagnostic: "provider has no token refresher")
            }
            fresh = try await service.refresh(refreshToken: refresh)
        } catch is RefreshRejected {
            // Stop keeping credentials the server has finished with — the
            // access token it granted last included. Without this the account
            // asks again on every poll, forever, with a credential it has been
            // told is dead — and the answer cannot change until the account is
            // signed into again, which is what the row now says.
            //
            // The account stays in the list. Removing it would hide the very
            // thing the reader needs to act on, and a sign-in gives it a
            // working token again the moment they do.
            if let index = accounts.firstIndex(where: { $0.id == id && $0.refreshToken == refresh }) {
                accounts[index].refreshToken = nil
                accounts[index].accessToken = nil
                accounts[index].accessGoodUntil = nil
                await persistRemembering()
            }
            throw ProviderFailure(
                kind: .needsLogin, diagnostic: "refresh token rejected; sign in again"
            )
        }

        guard let index = accounts.firstIndex(where: { $0.id == id && $0.refreshToken == refresh }) else {
            // Forgotten while the request was out. The reply belongs to
            // nobody: dropping it is the letting-go the forget promised.
            throw ProviderFailure(kind: .needsLogin, diagnostic: "account not found")
        }

        let before = accounts[index]
        if let rotated = fresh.refreshToken, !rotated.isEmpty {
            accounts[index].refreshToken = rotated
        }
        // Held only when the server said how long for. Absent that, nothing is
        // assumed and every poll fetches its own, as before.
        if let life = fresh.expiresIn, life.isFinite, life > Self.expiryMargin {
            accounts[index].accessToken = fresh.accessToken
            accounts[index].accessGoodUntil = now().addingTimeInterval(life - Self.expiryMargin)
        } else {
            accounts[index].accessToken = nil
            accounts[index].accessGoodUntil = nil
        }
        if accounts[index] != before { await persistRemembering() }
        return fresh.accessToken
    }

    /// The active CLI session's token. Re-read every time — the CLI may have
    /// refreshed it.
    public func currentCLIToken() async throws -> String {
        guard let token = try await cliOAuth()["accessToken"] as? String else {
            throw ProviderFailure(kind: .needsLogin, diagnostic: "claude code not signed in")
        }
        return token
    }

    private func currentCLIRefreshToken() async throws -> String {
        guard let token = try await cliOAuth()["refreshToken"] as? String else {
            throw ProviderFailure(kind: .needsLogin, diagnostic: "no refresh token in keychain")
        }
        return token
    }

    /// Which account is active. Matching goes by refresh token: it is unique per
    /// account and, unlike the access token, does not change on every refresh.
    /// Whether the next reads may put a dialog on screen.
    ///
    /// Off by default: reads happen on a five-minute timer, and a keychain
    /// dialog raised by a timer is one nobody is looking for — it blocks the
    /// read until answered, and the answer never comes. Raised only around
    /// something a person just asked for, where the dialog lands in front of
    /// them.
    private var promptAllowed = false

    /// Raised around something the person just asked for, and lowered after.
    ///
    /// A closure taking the whole poll would read better, but a poll is a
    /// `@MainActor` method and handing it to this actor is not something the
    /// compiler will allow across the boundary — so the switch is set and unset
    /// instead.
    public func setPromptAllowed(_ allowed: Bool) { promptAllowed = allowed }

    public var isPromptAllowed: Bool { promptAllowed }

    private func currentCLIAccountToken() async throws -> (handle: String, token: String) {
        let oauth = try await cliOAuth()
        guard let access = oauth["accessToken"] as? String,
              let refresh = oauth["refreshToken"] as? String,
              let match = accounts.first(where: { $0.provider == .claude && !$0.isOwnGrant && $0.refreshToken == refresh })
        else {
            throw ProviderFailure(kind: .needsLogin, diagnostic: "active account unrecognised")
        }
        return (match.handle, access)
    }

    /// Reads the keychain item owned by Claude Code.
    ///
    /// The result is held for `cacheWindow` seconds. One poll needs this data
    /// three times — to identify the active account, take its access token and
    /// copy the refresh token. macOS checks every access to another app's item
    /// separately, so without a cache the app would bother the system three
    /// times as often for nothing: the contents do not change within seconds.
    private func cliOAuth() async throws -> [String: Any] {
        if let cached = cliCache, now().timeIntervalSince(cached.readAt) < cacheWindow {
            return cached.oauth
        }

        guard let data = try await keychain.read(service: Self.cliService,
                                                 promptIfNeeded: promptAllowed),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any]
        else {
            throw ProviderFailure(kind: .needsLogin, diagnostic: "claude code not signed in")
        }

        cliCache = (oauth, now())
        return oauth
    }

    public func accountStates() async -> [(account: StoredAccount, state: AccountState)] {
        // Asking the CLI which account is active there is only worth a read of
        // its item while some account is still a copy taken from it. With every
        // account on a grant of its own the answer cannot change a single label,
        // and the read is the same foreign read the rest of this file avoids.
        var activeRefresh: String?
        if dependsOnCLI() { activeRefresh = try? await currentCLIRefreshToken() }

        return accounts.map { account in
            let state: AccountState
            if account.provider == .claude, !account.isOwnGrant,
               let activeRefresh, account.refreshToken == activeRefresh {
                state = .activeInCLI
            } else if account.refreshToken != nil {
                state = .refreshed
            } else {
                state = .needsLogin
            }
            return (account, state)
        }
    }

    /// Forgets the account along with its token copy.
    /// The keychain item owned by Claude Code is left alone — the CLI sign-in
    /// keeps working, which is what the interface promises.
    public func forget(handle: String) async throws {
        try await forget(id: "claude/\(handle)")
    }

    public func forget(id: String) async throws {
        try await changing { $0.removeAll { $0.id == id } }
    }

    /// Saves an account added through browser sign-in.
    /// It has its own token pair, unconnected to the CLI session, so it starts
    /// out in the "refreshed" state.
    public func addLoggedInAccount(
        uuid: String, displayName: String, refreshToken: String
    ) async throws {
        try await addLoggedInAccount(AuthenticatedAccount(
            account: AccountRef(id: "claude/\(uuid)", provider: .claude, handle: uuid,
                                lastKnownName: displayName),
            tokens: RefreshedTokens(accessToken: "", refreshToken: refreshToken)))
    }

    public func addLoggedInAccount(_ result: AuthenticatedAccount) async throws {
        let ref = result.account
        guard [.claude, .codex].contains(ref.provider), !ref.handle.isEmpty,
              ref.id == "\(ref.provider.rawValue)/\(ref.handle)",
              let refresh = result.tokens.refreshToken, !refresh.isEmpty else {
            throw ProviderFailure(kind: .needsLogin, diagnostic: "sign-in has no usable grant")
        }
        let life = result.tokens.expiresIn ?? 0
        let keepAccess = life.isFinite && life > Self.expiryMargin && !result.tokens.accessToken.isEmpty
        let until = keepAccess ? now().addingTimeInterval(life - Self.expiryMargin) : nil
        // The record is replaced, not updated, and the held access token goes
        // with it. A new grant supersedes whatever was held for this account:
        // updating in place would leave the app serving the previous grant's
        // token until it expired — the sign-in would look done and change
        // nothing for an hour.
        try await changing {
            $0.removeAll { $0.id == ref.id }
            $0.append(StoredAccount(
                id: ref.id, handle: ref.handle,
                displayName: ref.lastKnownName, refreshToken: refresh,
                tokenOrigin: .ownGrant,
                accessToken: keepAccess ? result.tokens.accessToken : nil,
                accessGoodUntil: until
            ))
        }
    }

    public func invalidateAccessToken(for ref: AccountRef, rejectedToken: String) async {
        guard let index = accounts.firstIndex(where: { $0.id == ref.id }),
              accounts[index].accessToken == rejectedToken else { return }
        accounts[index].accessToken = nil
        accounts[index].accessGoodUntil = nil
        await persistRemembering()
    }

    /// Changes the account list and saves it, or does neither.
    ///
    /// The two used to be separate steps: change, then persist. When persisting
    /// failed the list had already changed, so the window showed one thing and
    /// the keychain held another — an account forgotten until the next launch
    /// brought it back, or one added by a browser sign-in that was gone by
    /// morning. Whichever way it went, the app looked right and was not.
    private func changing(_ edit: (inout [StoredAccount]) -> Void) async throws {
        let previous = accounts
        edit(&accounts)
        do {
            try await persist()
        } catch {
            accounts = previous
            throw error
        }
        // Nothing is kept on behalf of an account that is no longer listed:
        // the held access token lives on the record and leaves with it.
    }

    /// Refuses to write when the item held something this build could not read.
    ///
    /// `load` leaves the list empty in that case, so an edit here would encode
    /// an empty or one-element list and put it where the tokens were. They
    /// cannot be fetched again: a refresh token is issued once and the copy is
    /// taken while the account is active in the CLI. Losing them signs every
    /// inactive account out for good.
    private func persist() async throws {
        guard !storedButUnreadable else { throw WouldOverwriteUnreadableAccounts() }
        let data = try JSONEncoder().encode(accounts)
        try await keychain.write(data, service: Self.ownService)
        unsavedChanges = false
    }

    /// Set when a change could not be written; a later successful write, from
    /// anywhere, clears it.
    private var unsavedChanges = false

    /// Persists, and remembers a failure instead of reporting it.
    ///
    /// This is the refresh path's persist, where giving up is not an option:
    /// the change being saved is the only copy of a rotated refresh token, the
    /// server has already retired the one it replaced, and no caller can do
    /// anything about a failed write. So the change stays in memory and is put
    /// in front of the keychain again on the next call — `try?` here once
    /// dropped a rotation on the floor, and the next launch asked the server
    /// with the retired token and was told to sign in again.
    private func persistRemembering() async {
        do {
            try await persist()
        } catch {
            unsavedChanges = true
        }
    }
}
