import Testing
import Foundation

/// The widget is not emptied by an account list the app could not open.
///
/// The keychain binds access to the signature that wrote the item, so an update
/// can arrive unable to read the accounts the previous one saved. The store
/// reports that rather than pretending the list is empty — but the poll built
/// on top of it still produces no readings, and the poll is what feeds the
/// widget. Published, that reading turns a widget showing four subscriptions
/// into "No accounts found": a sentence about accounts that are still there,
/// on a surface with no room to explain itself and no button to press.
///
/// Held by reading the source, like the rest of the widget's rules: the
/// alternative is a widget on a screen and a locked keychain item, which no
/// test can arrange.
@Suite struct TheWidgetIsNotBlankedByAClosedList {

    @Test func thePollAsksBeforeItPublishesNothing() throws {
        let model = try String(contentsOf: Self.appModel, encoding: .utf8)
        guard let poll = Self.function("poll", in: model) else {
            throw ScanIsLookingInTheWrongPlace(what: "poll", found: 0, least: 1)
        }
        guard let publish = poll.range(of: "publishToWidget(snapshots)") else {
            throw ScanIsLookingInTheWrongPlace(
                what: "publishToWidget(snapshots)", found: 0, least: 1)
        }

        let before = poll[..<publish.lowerBound]
        #expect(before.contains("accountsProblem()"), """
            the poll publishes its reading to the widget without asking whether \
            the account list could be read — an item this build cannot open \
            polls as no accounts, and that blanks a widget which had four
            """)
        #expect(before.contains("snapshots.isEmpty"), """
            the guard no longer turns on the reading being empty, so a real \
            reading could be withheld from the widget
            """)
    }

    /// The other direction, which matters just as much: a list that reads
    /// correctly and holds nothing — everything forgotten — must still reach the
    /// widget, or it would show accounts that are gone.
    ///
    /// The guard used to call `accountsProblem()` on the spot and this read
    /// `await accountsProblem() == nil`. The reason is now taken once at the top
    /// of the poll, because the limits window needs it while it is drawing — so
    /// what the guard turns on is the copy. The rule is unchanged and the
    /// spelling is not: what matters is that publishing is decided by whether
    /// the list could be read, not by whether the reading came back empty.
    @Test func anEmptyListThatWasReadIsStillPublished() throws {
        let model = try String(contentsOf: Self.appModel, encoding: .utf8)
        guard let poll = Self.function("poll", in: model) else {
            throw ScanIsLookingInTheWrongPlace(what: "poll", found: 0, least: 1)
        }
        #expect(poll.contains("savedAccountsProblem == nil"), """
            the guard no longer lets a readable empty list through — forgetting \
            every account would leave the widget showing them
            """)
    }

    /// Demo turning off clears the samples in the same turn, and that path
    /// hands an empty list over deliberately. It must not be made to ask.
    @Test func leavingDemoStillClearsTheSamplesAtOnce() throws {
        let model = try String(contentsOf: Self.appModel, encoding: .utf8)
        #expect(model.contains("publishToWidget([])"), """
            the deliberate clear when demo is switched off is gone — the desktop \
            would name a sample account for up to five minutes afterwards
            """)
    }

    private static func function(_ name: String, in source: String) -> String? {
        guard let start = source.range(of: "func \(name)(") else { return nil }
        let rest = source[start.upperBound...]
        guard let end = rest.range(of: "\n    }") else { return nil }
        return String(rest[..<end.lowerBound])
    }

    private static var appModel: URL { root.appendingPathComponent("App/AppModel.swift") }

    private static var root: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
}
