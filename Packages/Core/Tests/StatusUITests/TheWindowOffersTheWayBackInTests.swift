import Testing
import Foundation

/// An empty window must not send somebody to sign in again over accounts that
/// are only shut.
///
/// The keychain binds item access to the signature that wrote it, so an update
/// can be enough for a build to be refused its own saved list. Nothing is lost
/// when that happens: the refresh tokens are intact, the keychain will put its
/// question to the person, and their answer hands every account back. The store
/// has told that apart from a fresh install since 0.1.26 — `whyUnreadable()`
/// answers `nil` only when the item was genuinely not there.
///
/// The window did not ask. It branched on `lastUpdated` alone and said "No
/// accounts found" to both, which is a conclusion about the accounts in the one
/// case where the app has been refused the right to draw one — and the advice
/// under it spends a grant to replace a credential that still works.
///
/// These checks read the source rather than a rendered view: a popover cannot
/// be built in a test process, and what is held here is the shape of the
/// decision, which reads perfectly well in the code that makes it.
@Suite struct TheWindowOffersTheWayBackIn {

    // MARK: - the window asks before it concludes

    /// The order is the whole guarantee. A conclusion drawn above the question
    /// is a conclusion drawn without it.
    @Test func itAsksWhyTheListIsEmptyBeforeSayingNothingIsInIt() throws {
        let empty = try Self.emptyState()

        guard let asks = empty.range(of: "savedAccountsProblem"),
              let concludes = empty.range(of: "No accounts found") else {
            throw ScanIsLookingInTheWrongPlace(
                what: "the empty window's branches", found: 0, least: 2)
        }

        #expect(asks.lowerBound < concludes.lowerBound, """
            the empty window says "No accounts found" before asking whether the \
            saved list was refused — which is that sentence said to somebody \
            whose accounts are intact and one question away
            """)
    }

    /// And still after the older question, which `TheWindowSaysItIsStillLooking`
    /// holds on its own account. A refusal is known at launch and a poll is not,
    /// so asking about the refusal first would answer a question nobody has
    /// reached yet: the first poll is still running.
    @Test func itAsksWhetherAPollHasFinishedFirstOfAll() throws {
        let empty = try Self.emptyState()

        guard let looking = empty.range(of: "lastUpdated == nil"),
              let refused = empty.range(of: "savedAccountsProblem") else {
            throw ScanIsLookingInTheWrongPlace(
                what: "the empty window's branches", found: 0, least: 2)
        }

        #expect(looking.lowerBound < refused.lowerBound, """
            the empty window reports a refused list before it has established \
            that a poll finished at all
            """)
    }

    // MARK: - what it offers

    /// One way into the keychain, not two.
    ///
    /// `openSavedAccounts()` is where the dialog is allowed to be raised, where
    /// the refusal is written to the log, and where the window is kept open for
    /// as long as the question stands. A second path from this window would
    /// have all three to get right again.
    @Test func theWindowPressesTheSameRepairTheSettingsScreenDoes() throws {
        let offer = try Self.repairOffer()

        #expect(offer.contains("openSavedAccounts"), """
            the window's repair no longer goes through the model's \
            openSavedAccounts — the one place that raises the keychain's dialog \
            deliberately and holds the window open while it stands
            """)

        let settings = try String(contentsOf: Self.accountsPane, encoding: .utf8)
        #expect(settings.contains("openSavedAccounts"), """
            the settings screen has stopped calling openSavedAccounts, so the \
            two screens no longer repair the same way
            """)
    }

    /// Starting over deletes the only copy of every refresh token in the item.
    /// It is offered from the screen that asks about it first, and not from a
    /// window that opens under the pointer on a click of the menu bar.
    @Test func theWindowDoesNotOfferToThrowTheTokensAway() throws {
        let window = try String(contentsOf: Self.popover, encoding: .utf8)

        #expect(!window.contains("startAccountsOver"), """
            the limits window offers to start over, which deletes every refresh \
            token in the item — that belongs behind the settings screen's \
            confirmation, not in a popover
            """)
    }

    // MARK: - the one reason with no way out

    /// A list that opened and made no sense has nobody left to ask. Offering to
    /// ask anyway would put a button on screen that cannot work, and the
    /// heading that goes with it would promise accounts the app cannot produce.
    @Test func aListThatCannotBeUnderstoodIsOfferedNoQuestion() throws {
        let source = try String(contentsOf: Self.problem, encoding: .utf8)

        guard let property = Self.body(of: "var mayBeOpened: Bool {", in: source),
              let answer = property.range(of: "case .contentNotUnderstood:") else {
            throw ScanIsLookingInTheWrongPlace(
                what: "the mayBeOpened decision", found: 0, least: 1)
        }

        let afterwards = property[answer.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(afterwards.hasPrefix("false"), """
            a saved list this build opened and could not understand is offered \
            the keychain's question — which has nobody to put it to, and no \
            answer that would help
            """)
    }

    /// The good news is told only where it is true. Three reasons share this
    /// screen and only two of them mean the accounts are coming back.
    @Test func theHeadingPromisesTheAccountsOnlyWhereTheyAreComingBack() throws {
        let source = try String(contentsOf: Self.problem, encoding: .utf8)

        guard let heading = Self.body(of: "var heading: String {", in: source),
              let answer = heading.range(of: "case .contentNotUnderstood:") else {
            throw ScanIsLookingInTheWrongPlace(
                what: "the heading decision", found: 0, least: 1)
        }

        let afterwards = String(heading[answer.upperBound...])
        #expect(!afterwards.says("Your accounts are still here"), """
            a saved list this build cannot understand is headed "Your accounts \
            are still here" — a promise whose only way out is deleting them
            """)
        #expect(heading.says("Your accounts are still here"), """
            the window no longer tells anybody their accounts survived the \
            update, which is the one thing they need to read
            """)
    }

    // MARK: - the window is kept open while the dialog stands

    /// The keychain's question is a system dialog, and a `.transient` popover
    /// closes itself the moment the focus moves. Pressed without this, the
    /// window vanishes and a password prompt arrives with nothing on screen to
    /// say what asked for it.
    ///
    /// Released in `defer`, not on the way out: a refused dialog throws, and a
    /// count let go only on success would leave a popover that never closes by
    /// itself again.
    @Test func theRepairHoldsTheWindowOpenAndLetsGoWhicheverWayItEnds() throws {
        let source = try String(contentsOf: Self.appModel, encoding: .utf8)

        guard let repair = Self.body(of: "func openSavedAccounts() async throws {",
                                     in: source) else {
            throw ScanIsLookingInTheWrongPlace(
                what: "the repair on the model", found: 0, least: 1)
        }

        #expect(repair.contains("keychainDialogRequests += 1"), """
            the repair no longer holds the limits window open, so the keychain's \
            dialog closes the window that asked for it
            """)
        #expect(repair.contains("defer { keychainDialogRequests -= 1 }"), """
            the window is released somewhere other than a defer — a refused \
            dialog throws, and a popover left pinned never closes by itself \
            again
            """)
    }

    /// And the controller has to be listening, or the count is a number nobody
    /// reads.
    @Test func theStatusItemWatchesThatCount() throws {
        let source = try String(contentsOf: Self.statusItem, encoding: .utf8)

        #expect(source.contains("keychainDialogRequests"), """
            the status item no longer watches for a keychain dialog, so nothing \
            stops the popover closing itself while the question stands
            """)
        #expect(source.contains("applicationDefined"), """
            the status item no longer has a way to stop the popover closing \
            itself
            """)
    }

    // MARK: - reading

    private static func emptyState() throws -> String {
        let source = try String(contentsOf: popover, encoding: .utf8)
        guard let empty = body(of: "private var empty: some View {", in: source) else {
            throw ScanIsLookingInTheWrongPlace(
                what: "the empty state", found: 0, least: 1)
        }
        return empty
    }

    /// What the window draws once it has established the list was refused — the
    /// symbol, the sentences and the buttons. A branch of `empty` calls it, and
    /// the branching is what `emptyState()` above is for; these are two
    /// questions and they are asked of two regions on purpose.
    private static func repairOffer() throws -> String {
        let source = try String(contentsOf: popover, encoding: .utf8)
        guard let offer = body(
            of: "private func shut(_ problem: SavedAccountsProblem) -> some View {",
            in: source
        ) else {
            throw ScanIsLookingInTheWrongPlace(
                what: "the window's repair offer", found: 0, least: 1)
        }
        return offer
    }

    /// A declaration's body, from the brace that opens it to the one that
    /// closes it.
    ///
    /// Counted rather than cut at the next declaration, which is how the older
    /// suite does it: that one looks for the next `private var` and, when the
    /// property it wants is followed by a `func`, hands back the rest of the
    /// file. Everything it asks happens to be true of the rest of the file as
    /// well, so it passes — but a check that reads three properties when it
    /// means one is a check that will one day pass on a sentence in a property
    /// it was never pointed at.
    private static func body(of declaration: String, in source: String) -> String? {
        guard let start = source.range(of: declaration), declaration.hasSuffix("{")
        else { return nil }
        var depth = 1
        var index = start.upperBound
        while index < source.endIndex {
            switch source[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(source[start.upperBound..<index]) }
            default: break
            }
            index = source.index(after: index)
        }
        return nil
    }

    private static var popover: URL { root("App/PopoverView.swift") }
    private static var accountsPane: URL { root("App/Settings/AccountsPane.swift") }
    private static var problem: URL { root("App/SavedAccountsProblem.swift") }
    private static var appModel: URL { root("App/AppModel.swift") }
    private static var statusItem: URL { root("App/StatusItemController.swift") }

    private static func root(_ path: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path)
    }
}
