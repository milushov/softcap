import Foundation
import ProviderKit
import ClaudeProvider

/// The account list and token vending.
///
/// The account currently active in the CLI is read-only: refreshing may rotate
/// the token on the server side, leaving the CLI with a stale one and signing it
/// out. Inactive accounts have no such tie to the CLI, so they are refreshed
/// from their saved copy — which is what makes all subscriptions visible at once.
public actor CredentialStore: ClaudeTokenSource {
    public static let cliService = "Claude Code-credentials"
    /// Deliberately still the old name after the rename to Softcap. Keychain
    /// access is bound to the code signature, not to the bundle identifier, so
    /// the string can stay — and accounts gathered from the CLI are the one
    /// thing here that does not come back by itself.
    public static let ownService = "StatusChecker-accounts"

    private let keychain: any KeychainAccess
    private let refresher: any TokenRefreshing
    /// How long to hold what was read from the keychain. Enough for one poll;
    /// the CLI token does not expire in that time — it lives about eight hours.
    /// Tests pass zero so they can check reads without the delay.
    private let cacheWindow: TimeInterval
    private var accounts: [StoredAccount] = []
    private var cliCache: (oauth: [String: Any], readAt: Date)?

    /// Access tokens already fetched, by account handle, with the moment each
    /// stops being usable.
    ///
    /// Memory only. Writing them beside the refresh tokens would put a second
    /// kind of credential in the keychain to no purpose: an access token is
    /// cheap to obtain again, and a relaunch simply fetches one.
    private var accessCache: [String: (token: String, goodUntil: Date)] = [:]

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
        cacheWindow: TimeInterval = 10,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.keychain = keychain
        self.refresher = refresher
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
        accounts.isEmpty || accounts.contains { !$0.isOwnGrant }
    }

    public func knownRefs() -> [AccountRef] {
        accounts.map {
            AccountRef(id: $0.id, provider: .claude, handle: $0.handle,
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

        if let index = accounts.firstIndex(where: { $0.handle == profileUUID }) {
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
        guard let index = accounts.firstIndex(where: { $0.handle == handle }) else {
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
        if accounts[index].isOwnGrant {
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
            if active.handle == handle { return active.token }
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

        guard let refresh = accounts[index].refreshToken else {
            throw ProviderFailure(
                kind: .needsLogin, diagnostic: "no usable credential; sign in"
            )
        }
        return try await refreshing(at: index, with: refresh)
    }

    /// Trades a refresh token for an access token, keeping whatever the server
    /// hands back for next time.
    private func refreshing(at index: Int, with refresh: String) async throws -> String {
        // A token already in hand and not yet near its deadline serves this poll
        // as well as a new one would. Every refresh spends the refresh token —
        // the server rotates it on use — so a refresh made for no reason is a
        // rotation made for no reason, and each rotation is a chance for the
        // reply to be lost and the account left holding a retired credential.
        let handle = accounts[index].handle
        if let held = accessCache[handle], held.goodUntil > now() {
            return held.token
        }

        let fresh: RefreshedTokens
        do {
            fresh = try await refresher.refresh(refreshToken: refresh)
        } catch is RefreshRejected {
            // Stop keeping a token the server has finished with. Without this the
            // account asks again on every poll, forever, with a credential it has
            // been told is dead — and the answer cannot change until the account
            // is signed into again, which is what the row now says.
            //
            // The account stays in the list. Removing it would hide the very
            // thing the reader needs to act on, and a sign-in gives it a working
            // token again the moment they do.
            accounts[index].refreshToken = nil
            try? await persist()
            throw ProviderFailure(
                kind: .needsLogin, diagnostic: "refresh token rejected; sign in again"
            )
        }
        if let rotated = fresh.refreshToken {
            accounts[index].refreshToken = rotated
            try? await persist()
        }
        // Held only when the server said how long for. Absent that, nothing is
        // assumed and every poll fetches its own, as before.
        if let life = fresh.expiresIn, life > Self.expiryMargin {
            accessCache[handle] = (
                fresh.accessToken, now().addingTimeInterval(life - Self.expiryMargin)
            )
        } else {
            accessCache[handle] = nil
        }
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
              let match = accounts.first(where: { $0.refreshToken == refresh })
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
            if let activeRefresh, account.refreshToken == activeRefresh {
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
        try await changing { $0.removeAll { $0.handle == handle } }
    }

    /// Saves an account added through browser sign-in.
    /// It has its own token pair, unconnected to the CLI session, so it starts
    /// out in the "refreshed" state.
    public func addLoggedInAccount(
        uuid: String, displayName: String, refreshToken: String
    ) async throws {
        // A new grant supersedes whatever was held for this account. Without
        // this, re-signing-in would leave the app serving the previous grant's
        // token until it expired — the sign-in would look done and change
        // nothing for an hour.
        accessCache[uuid] = nil
        try await changing {
            $0.removeAll { $0.handle == uuid }
            $0.append(StoredAccount(
                id: "claude/\(uuid)", handle: uuid,
                displayName: displayName, refreshToken: refreshToken,
                tokenOrigin: .ownGrant
            ))
        }
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
        // Nothing is kept on behalf of an account that is no longer listed. The
        // held token is in memory rather than the keychain, but "not written
        // down" is not "let go of", and a token that outlives the account it
        // belongs to is a credential nobody is watching any more.
        let present = Set(accounts.map(\.handle))
        accessCache = accessCache.filter { present.contains($0.key) }
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
    }
}
