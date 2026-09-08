import Foundation
import ProviderKit
import ClaudeProvider

/// The server has finished with this refresh token: expired, revoked, or rotated
/// away by another client. Distinct from any other refresh failure because the
/// answer will not change — a network error is worth retrying in five minutes and
/// this is not, and a client that asks forever with a credential it has been told
/// is dead is a badly behaved one.
public struct RefreshRejected: Error, Sendable, Equatable {
    public init() {}
}

/// Thrown rather than writing over an account list that could not be read.
public struct WouldOverwriteUnreadableAccounts: Error, CustomStringConvertible {
    public var description: String {
        "the stored account list could not be read, and writing would replace the "
        + "only copy of every inactive account's refresh token"
    }
}

public struct StoredAccount: Sendable, Codable, Hashable {
    public let id: String
    public let handle: String
    public var displayName: String
    /// A copy of the refresh token, taken while the account was active in the
    /// CLI. `syncWithCLI` exists for its sake.
    public var refreshToken: String?
}

public protocol TokenRefreshing: Sendable {
    func refresh(refreshToken: String) async throws -> RefreshedTokens
}

/// Refreshing an Anthropic session. Endpoint and body shape verified on
/// 2026-08-30: a bogus token gets `400 invalid_grant`.
public struct AnthropicTokenRefresher: TokenRefreshing {
    private let http: any HTTPClient

    public init(http: any HTTPClient = URLSessionHTTPClient()) { self.http = http }

    public func refresh(refreshToken: String) async throws -> RefreshedTokens {
        let body = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": OAuthEndpoints.clientID,
        ])

        let (data, code) = try await http.post(
            OAuthEndpoints.token, headers: OAuthEndpoints.jsonHeaders, body: body
        )
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        // `invalid_grant` on 400 is the spec's way of saying this token is
        // finished: expired, revoked, or rotated away by whoever refreshed it
        // last. Asking again with the same token gets the same answer forever,
        // so the caller is told to stop keeping it rather than to try later.
        if code == 400, (root?["error"] as? String) == "invalid_grant" {
            throw RefreshRejected()
        }

        guard code == 200, let access = root?["access_token"] as? String else {
            throw ProviderFailure(kind: .needsLogin, diagnostic: "refresh failed, HTTP \(code)")
        }
        return RefreshedTokens(
            accessToken: access, refreshToken: root?["refresh_token"] as? String
        )
    }
}

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

    public init(
        keychain: any KeychainAccess,
        refresher: any TokenRefreshing,
        cacheWindow: TimeInterval = 10
    ) {
        self.keychain = keychain
        self.refresher = refresher
        self.cacheWindow = cacheWindow
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
            if let refresh { accounts[index].refreshToken = refresh }
        } else {
            accounts.append(StoredAccount(
                id: "claude/\(profileUUID)", handle: profileUUID,
                displayName: displayName, refreshToken: refresh
            ))
        }
        try await persist()
    }

    public func accessToken(for handle: String) async throws -> String {
        guard let index = accounts.firstIndex(where: { $0.handle == handle }) else {
            throw ProviderFailure(kind: .needsLogin, diagnostic: "account not found")
        }

        // The active account is recognised by matching the CLI keychain item.
        //
        // One failure is kept rather than swallowed: the keychain refusing to
        // read without a dialog. `try?` treated it like any other miss and the
        // account fell through to "sign-in required", which is the wrong
        // instruction — signing in again does nothing, and granting access does.
        // Whether this account is the one Claude Code is signed into. The answer
        // is unavailable when the keychain will not let us look — and that must
        // not condemn an account holding a perfectly good copy of its own.
        //
        // Written the other way round first, rethrowing the refusal here, on the
        // assumption that it was rare and specific to one account. It is neither:
        // the CLI's item is one item, so a refusal is refused for everybody, and
        // three accounts that had been polling happily all failed at once the
        // moment the refusal was correctly detected.
        var refusal: ProviderFailure?
        do {
            let active = try await currentCLIAccountToken()
            if active.handle == handle { return active.token }
        } catch let failure as ProviderFailure where failure.kind == .needsPermission {
            refusal = failure
        } catch {
            // Any other reason is fine here: the account is simply not the
            // active one, and its own copy is next.
        }

        guard let refresh = accounts[index].refreshToken else {
            // Now the refusal matters: with no copy of its own, this account can
            // only be read through the CLI's item, and that is what was refused.
            throw refusal ?? ProviderFailure(
                kind: .needsLogin, diagnostic: "no usable refresh token; sign in again"
            )
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
            // thing the reader needs to act on, and `syncWithCLI` gives it a
            // working token again the moment they do.
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
        if let cached = cliCache, Date().timeIntervalSince(cached.readAt) < cacheWindow {
            return cached.oauth
        }

        guard let data = try await keychain.read(service: Self.cliService,
                                                 promptIfNeeded: promptAllowed),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any]
        else {
            throw ProviderFailure(kind: .needsLogin, diagnostic: "claude code not signed in")
        }

        cliCache = (oauth, Date())
        return oauth
    }

    /// How the app obtains a token for this account right now.
    /// Computed rather than stored: the state depends on who the user is signed
    /// in as in the CLI, not on our records.
    public enum AccountState: Sendable, Hashable {
        case activeInCLI   // token read from the CLI keychain, never refreshed
        case refreshed     // lives on its own refresh token copy
        case needsLogin    // no copy, nothing to refresh with
    }

    public func accountStates() async -> [(account: StoredAccount, state: AccountState)] {
        let activeRefresh = try? await currentCLIRefreshToken()

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

    /// Drops an account's own copy while keeping the account. Exists for the
    /// tests: the same thing happens in life when the server rejects a token,
    /// and there is no other way to reach that state from outside.
    public func forgetCopyForTesting(handle: String) {
        guard let index = accounts.firstIndex(where: { $0.handle == handle }) else { return }
        accounts[index].refreshToken = nil
    }

    /// Saves an account added through browser sign-in.
    /// It has its own token pair, unconnected to the CLI session, so it starts
    /// out in the "refreshed" state.
    public func addLoggedInAccount(
        uuid: String, displayName: String, refreshToken: String
    ) async throws {
        try await changing {
            $0.removeAll { $0.handle == uuid }
            $0.append(StoredAccount(
                id: "claude/\(uuid)", handle: uuid,
                displayName: displayName, refreshToken: refreshToken
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
