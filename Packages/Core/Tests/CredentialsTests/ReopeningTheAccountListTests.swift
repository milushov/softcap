import Testing
import Foundation
import Security
import ProviderKit
@testable import Credentials

/// Getting back into an account list this build cannot read.
///
/// The keychain binds access to the signature that wrote the item, and a build
/// signed ad-hoc is a different application every time it is built. So an
/// update takes the accounts away: the list reads as empty, and — because the
/// item is the only copy of every refresh token — nothing may be written over
/// it. That guard is right, and on its own it is a dead end: no accounts, no
/// sign-in, and a sentence that says only "Sign-in did not complete".
///
/// The way out was measured before it was written. Reading the item with the
/// keychain's own question allowed returns it in full, so the accounts are not
/// lost — only closed. Deleting by reference replaces the item outright and
/// the new one belongs to this build, so starting over is a real last resort
/// rather than a write into something that can never be read back.
private actor OneItemKeychain: KeychainAccess {
    enum Behaviour: Sendable {
        /// Reading is refused unless the question is put to the person.
        case refusesUntilAsked
        /// Refused either way: the person said no, or was never there.
        case refusesAlways
        /// Opens without asking.
        case open
    }

    private var stored: Data?
    private let behaviour: Behaviour
    private(set) var quietReads = 0
    private(set) var askedReads = 0
    private(set) var writes = 0
    private(set) var replacements = 0

    /// Whether the question stays on screen until the test dismisses it. A
    /// keychain dialog is answered by a person, so the only honest model of it
    /// is one that does not return until somebody says so — and a repair that
    /// returns instantly cannot be caught arriving twice.
    private let holdsTheQuestion: Bool
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// What the keychain says when it will not hand the item over. The default
    /// is the access check turning this caller away; a test that wants the
    /// other kind of refusal passes another.
    private let refusal: OSStatus

    /// Set when the replacement deletes the old item and then fails, which is
    /// the one failure that destroys tokens rather than preserving them.
    private let losesTheItemOnReplace: Bool

    init(
        _ stored: Data?, behaviour: Behaviour, holdsTheQuestion: Bool = false,
        refusal: OSStatus = errSecAuthFailed, losesTheItemOnReplace: Bool = false
    ) {
        self.stored = stored
        self.behaviour = behaviour
        self.holdsTheQuestion = holdsTheQuestion
        self.refusal = refusal
        self.losesTheItemOnReplace = losesTheItemOnReplace
    }

    /// Answers every question standing open.
    func answerTheQuestion() {
        for continuation in waiting { continuation.resume() }
        waiting.removeAll()
    }

    func read(service: String) throws -> Data? {
        quietReads += 1
        guard behaviour == .open else { throw KeychainDidNotOpen(status: refusal) }
        return stored
    }

    func readAllowingPrompt(service: String) async throws -> Data? {
        askedReads += 1
        if holdsTheQuestion {
            // Suspends this call and lets the actor go, which is exactly what
            // the real one does while the dialog stands open.
            await withCheckedContinuation { waiting.append($0) }
        }
        guard behaviour != .refusesAlways else { throw KeychainDidNotOpen(status: refusal) }
        return stored
    }

    func write(_ data: Data, service: String) throws {
        writes += 1
        stored = data
    }

    /// The item is gone and a new one put in its place; this build can read it
    /// afterwards, which is the whole point of replacing rather than writing.
    func replace(_ data: Data, service: String) throws {
        replacements += 1
        guard !losesTheItemOnReplace else {
            stored = nil
            throw TheItemWasDeletedAndNotReplaced(status: errSecIO)
        }
        stored = data
    }

    var contents: Data? { stored }
}

private actor QuietRefresher: TokenRefreshing {
    func refresh(refreshToken: String) async throws -> RefreshedTokens {
        RefreshedTokens(accessToken: "fresh", refreshToken: "rotated")
    }
}

private func savedList() throws -> Data {
    try JSONEncoder().encode([
        StoredAccount(id: "claude/a", handle: "a", displayName: "A",
                      refreshToken: "the-only-copy", tokenOrigin: .ownGrant)
    ])
}

@Suite struct ReopeningTheAccountList {

    // ===== saying which of the two it is =====

    @Test func aRefusedReadIsNotTheSameAsRubbishInTheItem() async throws {
        let refused = OneItemKeychain(try savedList(), behaviour: .refusesAlways)
        let store = CredentialStore(keychain: refused, refresher: QuietRefresher())
        await store.load()
        #expect(await store.whyUnreadable() == .keychainRefusedThisBuild)

        let rubbish = OneItemKeychain(Data("not json".utf8), behaviour: .open)
        let second = CredentialStore(keychain: rubbish, refresher: QuietRefresher())
        await second.load()
        #expect(await second.whyUnreadable() == .contentNotUnderstood)
    }

    @Test func aListThatOpenedHasNothingWrongWithIt() async throws {
        let keychain = OneItemKeychain(try savedList(), behaviour: .open)
        let store = CredentialStore(keychain: keychain, refresher: QuietRefresher())
        await store.load()
        #expect(await store.whyUnreadable() == nil)
    }

    /// Launch never puts the question on screen. That is the decision this app
    /// nearly died of: a keychain prompt raised by a poll, in an app with no
    /// Dock icon, answered by nobody, held the whole store for eighty-four
    /// minutes. Asking happens when a person asks for it, and at no other time.
    @Test func launchDoesNotAsk() async throws {
        let keychain = OneItemKeychain(try savedList(), behaviour: .refusesUntilAsked)
        let store = CredentialStore(keychain: keychain, refresher: QuietRefresher())
        await store.load()
        #expect(await keychain.askedReads == 0)
    }

    /// A locked keychain is not a signature that no longer matches, and the
    /// screen says different things about them. Told the wrong one, a person
    /// whose accounts are perfectly safe is invited to delete them.
    @Test func aKeychainThatCouldNotAnswerIsNotBlamedOnTheSignature() async throws {
        let locked = OneItemKeychain(
            try savedList(), behaviour: .refusesAlways, refusal: errSecInteractionNotAllowed)
        let store = CredentialStore(keychain: locked, refresher: QuietRefresher())
        await store.load()
        #expect(await store.whyUnreadable() == .keychainRefusedThisBuild,
                "a refused access check is about this build")

        let broken = OneItemKeychain(try savedList(), behaviour: .refusesAlways, refusal: errSecIO)
        let second = CredentialStore(keychain: broken, refresher: QuietRefresher())
        await second.load()
        #expect(await second.whyUnreadable() == .keychainDidNotOpen,
                "a keychain that could not answer was reported as a signature mismatch")
    }

    // ===== opening it =====

    @Test func askingGetsTheAccountsBack() async throws {
        let keychain = OneItemKeychain(try savedList(), behaviour: .refusesUntilAsked)
        let store = CredentialStore(keychain: keychain, refresher: QuietRefresher())
        await store.load()
        #expect(await store.knownRefs().isEmpty)

        try await store.openWithPermission()

        #expect(await store.whyUnreadable() == nil)
        #expect(await store.knownRefs().map(\.id) == ["claude/a"])
    }

    /// The point of getting back in: a sign-in can be saved again, and it is
    /// saved beside the account that was already there rather than over it.
    @Test func andASignInCanBeSavedAgain() async throws {
        let keychain = OneItemKeychain(try savedList(), behaviour: .refusesUntilAsked)
        let store = CredentialStore(keychain: keychain, refresher: QuietRefresher())
        await store.load()
        try await store.openWithPermission()

        try await store.addLoggedInAccount(
            uuid: "b", displayName: "B", refreshToken: "second")

        #expect(await store.knownRefs().count == 2)
        #expect(await keychain.writes == 1)
    }

    @Test func aRefusalChangesNothingAndKeepsTheGuardUp() async throws {
        let keychain = OneItemKeychain(try savedList(), behaviour: .refusesAlways)
        let store = CredentialStore(keychain: keychain, refresher: QuietRefresher())
        await store.load()

        await #expect(throws: (any Error).self) { try await store.openWithPermission() }

        #expect(await store.whyUnreadable() == .keychainRefusedThisBuild)
        await #expect(throws: WouldOverwriteUnreadableAccounts.self) {
            try await store.addLoggedInAccount(uuid: "b", displayName: "B", refreshToken: "x")
        }
        #expect(await keychain.writes == 0, "the item that could not be read was written to")
    }

    /// Rubbish in the item cannot be opened by asking: there is nobody to ask
    /// and nothing they could say. The reason stays what it was.
    @Test func askingDoesNotHelpWhenTheContentIsTheProblem() async throws {
        let keychain = OneItemKeychain(Data("not json".utf8), behaviour: .open)
        let store = CredentialStore(keychain: keychain, refresher: QuietRefresher())
        await store.load()

        await #expect(throws: (any Error).self) { try await store.openWithPermission() }
        #expect(await store.whyUnreadable() == .contentNotUnderstood)
    }

    /// Two presses, one question.
    ///
    /// An actor is reentrant at every `await`, and the keychain's question is
    /// the longest `await` in the app — it lasts as long as the person looking
    /// at it. So a second press arrives while the first still stands, and
    /// without a guard it puts a second dialog on screen for the same item.
    ///
    /// The count is taken before the question is answered and checked after
    /// everything has finished: a test that waited on the second attempt
    /// instead would hang rather than fail on the day the guard is removed,
    /// and a suite that hangs says nothing to the person who removed it.
    @Test func aSecondAttemptWhileTheQuestionStandsAsksNothing() async throws {
        let keychain = OneItemKeychain(
            try savedList(), behaviour: .refusesUntilAsked, holdsTheQuestion: true)
        let store = CredentialStore(keychain: keychain, refresher: QuietRefresher())
        await store.load()

        async let first: Void = store.openWithPermission()
        while await keychain.askedReads == 0 { await Task.yield() }

        async let second: Void = store.openWithPermission()
        // Every chance to reach the keychain, if it were going to.
        for _ in 0..<100 { await Task.yield() }
        let askedWhileTheFirstStood = await keychain.askedReads

        await keychain.answerTheQuestion()
        _ = try await (first, second)

        #expect(askedWhileTheFirstStood == 1, "a second dialog was raised for the same item")
        #expect(await store.whyUnreadable() == nil)
        #expect(await store.knownRefs().map(\.id) == ["claude/a"])
    }

    // ===== starting over =====

    /// Replaced, not written to. A write leaves the old item in place with the
    /// access it already had — measured: an update from a build the item does
    /// not belong to succeeds, and the item still cannot be read afterwards.
    /// That would put the new accounts somewhere the app can never open again.
    @Test func startingOverReplacesTheItemRatherThanWritingToIt() async throws {
        let keychain = OneItemKeychain(try savedList(), behaviour: .refusesAlways)
        let store = CredentialStore(keychain: keychain, refresher: QuietRefresher())
        await store.load()

        try await store.startOver()

        #expect(await keychain.replacements == 1)
        #expect(await keychain.writes == 0)
        #expect(await store.whyUnreadable() == nil)
        #expect(await store.knownRefs().isEmpty)
    }

    @Test func andTheNextSignInIsSaved() async throws {
        let keychain = OneItemKeychain(try savedList(), behaviour: .refusesAlways)
        let store = CredentialStore(keychain: keychain, refresher: QuietRefresher())
        await store.load()
        try await store.startOver()

        try await store.addLoggedInAccount(uuid: "b", displayName: "B", refreshToken: "second")

        #expect(await store.knownRefs().map(\.id) == ["claude/b"])
    }

    /// The replacement deletes and then adds, and the add can fail after the
    /// delete has already happened. What the item held is gone at that point,
    /// so the guard protecting it is guarding nothing — and left up it would
    /// refuse every write for the rest of the install.
    @Test func aReplacementThatLosesTheItemDoesNotLeaveTheGuardUp() async throws {
        let keychain = OneItemKeychain(
            try savedList(), behaviour: .refusesAlways, losesTheItemOnReplace: true)
        let store = CredentialStore(keychain: keychain, refresher: QuietRefresher())
        await store.load()

        try await store.startOver()

        #expect(await store.whyUnreadable() == nil,
                "the guard is still up over tokens that no longer exist")
        try await store.addLoggedInAccount(uuid: "b", displayName: "B", refreshToken: "second")
        #expect(await store.knownRefs().map(\.id) == ["claude/b"])
    }

    /// It throws away every refresh token in the item, so it may only be
    /// reached from the one state where they are unreachable anyway.
    @Test func aHealthyListIsNeverStartedOver() async throws {
        let keychain = OneItemKeychain(try savedList(), behaviour: .open)
        let store = CredentialStore(keychain: keychain, refresher: QuietRefresher())
        await store.load()

        await #expect(throws: (any Error).self) { try await store.startOver() }

        #expect(await keychain.replacements == 0)
        #expect(await store.knownRefs().map(\.id) == ["claude/a"])
    }
}
