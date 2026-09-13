import Testing
import Foundation

/// An empty window must not claim an answer it does not have yet.
///
/// The first poll after a fresh install takes a while: the keychain is read, two
/// services are asked over the network, and none of it has returned by the time
/// somebody clicks the icon. The window drew its empty state regardless — "No
/// accounts found", and under it the advice to go and sign in. Both sentences
/// are a conclusion, stated in the one moment the app has not yet looked.
///
/// It was read exactly as it was written. The app was installed, the icon
/// clicked, the window said nothing was there, and it was put away as broken —
/// a minute before the accounts arrived.
///
/// `lastUpdated` is the difference: `nil` until a poll completes, set even when
/// that poll found nothing. So the distinction the reader needs is already in
/// the model, and this holds the window to using it. The spinner in the header
/// is not enough on its own — it is a control in the corner arguing with a
/// sentence in the middle, and the sentence wins.
@Suite struct TheWindowSaysItIsStillLooking {

    @Test func theEmptyWindowChecksWhetherAPollHasFinished() throws {
        let source = try String(contentsOf: Self.popover, encoding: .utf8)

        guard let empty = Self.emptyState(in: source) else {
            throw ScanIsLookingInTheWrongPlace(what: "the empty state", found: 0, least: 1)
        }

        #expect(empty.contains("lastUpdated == nil"), """
            the window's empty state no longer asks whether a poll has finished — \
            on a fresh install it states "No accounts found" while the first one is \
            still running, which is how it was mistaken for a broken app
            """)
    }

    /// Order matters as much as presence: the check has to come first, or the
    /// conclusion is drawn before the question is asked.
    @Test func itAsksBeforeItConcludes() throws {
        let source = try String(contentsOf: Self.popover, encoding: .utf8)

        guard let empty = Self.emptyState(in: source),
              let asks = empty.range(of: "lastUpdated == nil"),
              let concludes = empty.range(of: "No accounts found") else {
            throw ScanIsLookingInTheWrongPlace(what: "both branches", found: 0, least: 2)
        }

        #expect(asks.lowerBound < concludes.lowerBound, """
            the empty window concludes "No accounts found" before checking whether \
            anything has been read yet
            """)
    }

    /// The sentence shown while looking says so plainly, and is in every
    /// catalogue — `NoOrphanStrings` and `LocalizationTests` hold the ten
    /// languages to each other, this holds the window to the phrase.
    @Test func theLookingSentenceIsTheOneOnScreen() throws {
        let source = try String(contentsOf: Self.popover, encoding: .utf8)
        #expect(source.contains("\"Looking for your accounts…\""), """
            the window no longer shows the sentence that says it is still looking
            """)
    }

    // MARK: - reading

    /// The `empty` computed property, from its declaration to the start of the
    /// next one. Taken by shape rather than by line number, which a later edit
    /// would move.
    private static func emptyState(in source: String) -> String? {
        guard let start = source.range(of: "private var empty: some View {") else { return nil }
        let rest = source[start.upperBound...]
        guard let end = rest.range(of: "\n    private var ") else { return String(rest) }
        return String(rest[..<end.lowerBound])
    }

    private static var popover: URL {
        repositoryRoot.appendingPathComponent("App/PopoverView.swift")
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
