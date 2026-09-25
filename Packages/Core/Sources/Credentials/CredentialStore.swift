import Foundation
import ProviderKit
import ClaudeProvider

/// The account list and token vending.
///
/// Every account here arrived through the browser and holds a grant of this
/// app's own, refreshed from its saved copy. Nothing is read from any other
/// app's keychain item, which is why nothing here ever asks permission.
public actor CredentialStore: ClaudeTokenSource, AccountTokenSource {
    /// Deliberately still the old name after the rename to Softcap. Keychain
    /// access is bound to the code signature, not to the bundle identifier, so
    /// the string can stay — and the refresh tokens stored under it are the one
    /// thing here that does not come back by itself.
    public static let ownService = "StatusChecker-accounts"

    private let keychain: any KeychainAccess
    private let refreshers: [ProviderID: any TokenRefreshing]
    private var accounts: [StoredAccount] = []

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
        // Registered although this service usually issues nothing to rotate:
        // the flag on `ProviderID` decides what an *absent* refresh token
        // means, and a present one still has to have somewhere to go.
        copilotRefresher: any TokenRefreshing = GitHubTokenRefresher(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.keychain = keychain
        self.refreshers = [
            .claude: refresher, .codex: codexRefresher, .copilot: copilotRefresher,
        ]
        self.now = now
    }

    /// Set when the item could not be read, or was read and could not be
    /// understood — as opposed to there being nothing stored yet. The difference
    /// decides whether it is safe to write.
    ///
    /// Which of the two it is decides what can be done about it, so it is kept
    /// rather than flattened into a flag: one of them opens again for the price
    /// of a question put to the person, and the other never opens at all.
    private var unreadable: UnreadableAccountList?

    /// What the keychain said, kept for the log.
    ///
    /// The reason above is what the interface acts on; this is the line that
    /// still says `-25293` to whoever reads the log a month later. Without it
    /// the log recorded that a sign-in had failed because the list was
    /// unreadable, and never once said why the list was unreadable.
    public private(set) var unreadableDiagnostic: String?

    /// Why the saved list could not be read, or `nil` when it reads correctly.
    public func whyUnreadable() -> UnreadableAccountList? { unreadable }

    /// Whether a repair is already under way.
    ///
    /// An actor is reentrant at every `await`, and both repairs suspend on one:
    /// the keychain's question takes as long as the person takes to answer it.
    /// Without this a second press — or a second caller — puts a second dialog
    /// on screen for the same item, and the person answers the same question
    /// twice to no further effect. The same reasoning as `refreshInFlight`
    /// above, where a second caller spent a token the first had already
    /// rotated away.
    private var repairing = false

    /// Reads the saved list. Called once, right after construction.
    public func load() async {
        let data: Data?
        do {
            data = try await keychain.read(service: Self.ownService)
        } catch {
            // The item was not read at all — a locked keychain, or an access
            // check the signature no longer satisfies. That is not the same as
            // nothing being stored, and the two used to be one `try?`: the list
            // came back empty and the next edit encoded that empty list over
            // the only copy of every account's refresh token. A token is issued
            // once; there is nowhere to fetch it from again.
            //
            // Launch does not ask. The question the keychain would put on
            // screen here is the one that stopped this app dead for
            // eighty-four minutes; it is put by `openWithPermission()`, when a
            // person presses the button that says so.
            // Which refusal it was decides what the screen is allowed to say.
            // Every status used to arrive here as the same one, so a keychain
            // that was merely locked was reported as a signature that no longer
            // matches — a cause stated as fact beside a button that deletes
            // every token in the item.
            unreadable = (error as? KeychainDidNotOpen)?.isAboutThisBuild == true
                ? .keychainRefusedThisBuild : .keychainDidNotOpen
            unreadableDiagnostic = String(describing: error)
            return
        }
        guard let data else { return }   // nothing stored yet: a fresh install
        guard let stored = try? JSONDecoder().decode([StoredAccount].self, from: data) else {
            // Something is in the item and this build cannot read it. The list
            // stays empty so the interface says so — but nothing may be written
            // over it, because what is in there is the only copy of every
            // account's refresh token.
            unreadable = .contentNotUnderstood
            unreadableDiagnostic = "the stored list is not a list of accounts"
            return
        }
        accounts = stored
    }

    /// Asks the keychain to open the item, letting it put its question to the
    /// person, and takes the accounts back if it does.
    ///
    /// This is the cheap way out of the common case, and it costs nothing: the
    /// accounts were never gone, only shut, and what comes back is every
    /// refresh token that was ever written. Reached from a button and from
    /// nowhere else — not from launch, not from a poll — which is what keeps
    /// the old hazard away. The read it makes waits off this actor, so the app
    /// stays alive for as long as the dialog stands open.
    public func openWithPermission() async throws {
        guard unreadable != nil, !repairing else { return }
        repairing = true
        defer { repairing = false }
        let data = try await keychain.readAllowingPrompt(service: Self.ownService)
        guard let data else {
            // Nothing there after all: the item went away between the refusal
            // and the question. A fresh install is not an error, and writing
            // is safe again because there is nothing left to write over.
            unreadable = nil
            unreadableDiagnostic = nil
            return
        }
        guard let stored = try? JSONDecoder().decode([StoredAccount].self, from: data) else {
            // Opened, and what is inside still cannot be understood. The reason
            // changes, because what can be done about it changes with it.
            unreadable = .contentNotUnderstood
            unreadableDiagnostic = "the stored list is not a list of accounts"
            throw AccountListStayedShut()
        }
        accounts = stored
        unreadable = nil
        unreadableDiagnostic = nil
    }

    /// Throws the unreadable item away and puts an empty one this build owns in
    /// its place.
    ///
    /// The last resort, and it is destructive: every refresh token in the old
    /// item goes with it, and each account it held has to be signed in again.
    /// Offered only from the state where those tokens are unreachable anyway,
    /// and refused from every other — `NothingToStartOverFrom` rather than a
    /// silent wipe of a list that was fine.
    ///
    /// Replaced rather than written over. A write would succeed and leave the
    /// old item's access control in place, so the new accounts would land
    /// somewhere this build can never read back — the same dead end again, with
    /// the tokens now lost as well.
    public func startOver() async throws {
        guard unreadable != nil else { throw NothingToStartOverFrom() }
        guard !repairing else { return }
        repairing = true
        defer { repairing = false }
        let empty = try JSONEncoder().encode([StoredAccount]())
        do {
            try await keychain.replace(empty, service: Self.ownService)
        } catch let loss as TheItemWasDeletedAndNotReplaced {
            // The old item is gone and nothing took its place, which is most of
            // what starting over means. The guard comes down with it: it exists
            // to protect tokens that no longer exist, and left up it would
            // refuse every write from here to the end of the install. The next
            // write adds a fresh item, which is what the failed step was for.
            accounts = []
            unreadable = nil
            unreadableDiagnostic = String(describing: loss)
            unsavedChanges = true
            return
        }
        accounts = []
        unreadable = nil
        unreadableDiagnostic = nil
        unsavedChanges = false
    }

    public func knownRefs() -> [AccountRef] {
        accounts.map {
            AccountRef(id: $0.id, provider: $0.provider, handle: $0.handle,
                       lastKnownName: $0.displayName)
        }
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

        // Only a grant of this app's own may be refreshed.
        //
        // An account whose token was copied from Claude Code carries *its*
        // refresh token, and the server rotates a refresh token when it is
        // spent. Refreshing one of those would hand Claude Code a retired
        // credential and sign it out — an app for watching limits breaking the
        // tool it watches. Those copies could be spent while the app also read
        // the CLI's item and could see what had happened; it no longer does, so
        // the only safe thing to do with one is to leave it alone and ask for a
        // browser sign-in, which produces a grant that belongs to us.
        //
        // `tokenOrigin == nil` means a list written before the field existed,
        // which cannot say where the token came from. A browser sign-in made by
        // a build from that week also recorded nothing, so `nil` is not proof of
        // a CLI copy — but it is not proof of a grant either, and only one of
        // the two mistakes signs somebody else's tool out. So `nil` is refused
        // and the row asks for the sign-in that settles it.
        guard accounts[index].isSpendable else {
            throw ProviderFailure(
                kind: .needsLogin,
                diagnostic: "token was copied from the CLI and must not be spent; sign in"
            )
        }

        // A grant from a service that does not rotate is served as it is.
        //
        // For Anthropic and OpenAI, no refresh token means the grant has been
        // spent, and the guard below is what stops a dead account being retried
        // on every poll forever. A device grant for a public GitHub client has
        // no refresh token to begin with and its access token does not expire —
        // the same absence, the opposite meaning. Reading it as "spent" would
        // report "sign in again" about a token that answers, on every poll, and
        // no sign-in would ever change it because the next one would produce a
        // credential of exactly the same shape.
        //
        // Narrow on purpose. It applies only where the service says rotation is
        // not its model, only when there is genuinely nothing to refresh with,
        // and only to a token that has not been given a deadline it is past. A
        // service that does rotate reaches none of this and keeps today's
        // behaviour unchanged, which is the property `CredentialStoreTests`
        // holds in one file beside this one.
        if !accounts[index].provider.rotatesCredentials,
           accounts[index].refreshToken == nil,
           let held = accounts[index].accessToken, !held.isEmpty,
           accounts[index].accessGoodUntil.map({ $0 > now() }) ?? true {
            return held
        }

        guard let refresh = accounts[index].refreshToken else {
            throw ProviderFailure(kind: .needsLogin, diagnostic: "own grant spent; sign in")
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

    public func accountStates() -> [(account: StoredAccount, state: AccountState)] {
        accounts.map { account in
            // A token copied from Claude Code cannot be spent — see
            // `accessToken(for:)` — so an account still holding one needs a
            // browser sign-in exactly as much as an account holding nothing.
            // Saying `refreshed` because a string is present would promise a
            // reading that can never arrive.
            // The same question `accessToken(for:)` answers, asked the same
            // way. It was `isOwnGrant && refreshToken != nil`, which is true
            // only of a service that rotates — so a device grant and a key
            // given by hand, both of which hold no refresh token because there
            // is nothing to rotate, were reported as needing a sign-in while
            // the poller was reading their limits perfectly well. A red badge
            // and a `Sign in…` button, forever, on an account that worked.
            //
            // `TheRowStateAgreesWithTheToken` holds the two together, because
            // one of them being updated and not the other is exactly how this
            // arrived.
            let holdsSomethingToSpend = account.refreshToken != nil
                || (!account.provider.rotatesCredentials && !(account.accessToken ?? "").isEmpty)
            let state: AccountState =
                account.isSpendable && holdsSomethingToSpend ? .refreshed : .needsLogin
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

    /// The services a sign-in can produce an account for. A provider absent
    /// here is one the app names but cannot yet be signed into, and a grant
    /// claiming to be from one is refused rather than stored unreadably.
    private static let signInCapable: Set<ProviderID> = [.claude, .codex, .copilot, .glm]

    public func addLoggedInAccount(_ result: AuthenticatedAccount) async throws {
        let ref = result.account
        guard Self.signInCapable.contains(ref.provider), !ref.handle.isEmpty,
              ref.id == "\(ref.provider.rawValue)/\(ref.handle)" else {
            throw ProviderFailure(kind: .needsLogin, diagnostic: "sign-in has no usable grant")
        }

        // What makes a grant usable depends on what the service issues. A
        // rotating service must hand over a refresh token, because its access
        // token is short-lived and an account holding only that one is an
        // account that stops working within the hour. A service that does not
        // rotate issues no refresh token at all, and for it the access token is
        // the grant — requiring one that will never come would refuse every
        // sign-in it can make.
        let refresh = result.tokens.refreshToken.flatMap { $0.isEmpty ? nil : $0 }
        let isStatic = !ref.provider.rotatesCredentials
        let hasAccess = !result.tokens.accessToken.isEmpty
        guard refresh != nil || (isStatic && hasAccess) else {
            throw ProviderFailure(kind: .needsLogin, diagnostic: "sign-in has no usable grant")
        }

        let life = result.tokens.expiresIn ?? 0
        let stated = life.isFinite && life > Self.expiryMargin && hasAccess
        // A static grant keeps its token with no deadline beside it. The service
        // did not state one, and a guessed deadline would retire a token that
        // goes on working — the same reason `RefreshedTokens.expiresIn` refuses
        // to assume a lifetime.
        let keepAccess = stated || (isStatic && hasAccess)
        let until = stated ? now().addingTimeInterval(life - Self.expiryMargin) : nil
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
                tokenOrigin: ref.provider.credentialIsGivenByHand ? .givenByHand : .ownGrant,
                accessToken: keepAccess ? result.tokens.accessToken : nil,
                accessGoodUntil: until
            ))
        }
    }

    public func invalidateAccessToken(for ref: AccountRef, rejectedToken: String) async {
        // A static grant is not a cached copy of anything, so there is nothing
        // to throw away and fetch again — the stored token *is* the grant, and
        // discarding it on one refused request would destroy the account over a
        // status the next poll might not repeat. A genuinely revoked token goes
        // on being refused, and the row says so and offers the sign-in; a
        // momentary one costs a single retry and then works.
        guard ref.provider.rotatesCredentials else { return }
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
        guard unreadable == nil else { throw WouldOverwriteUnreadableAccounts() }
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
