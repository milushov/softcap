import Testing
import Foundation

/// The minimal row can show its other period on a click, and the click is
/// deliberately worth nothing tomorrow: the peek lives in the view, dies with
/// the window, and is written to no store.
///
/// Scanned out of the source for the reason `TheWindowCanFixASignIn` gives:
/// these are views, the package tests are the only tests this project has,
/// and a scan cannot prove a screen behaves — it can prove the claim is
/// still written.
@Suite struct ThePeekIsNotRemembered {

    /// View-local state, not a preference. The one declaration that makes
    /// the peek forgettable at all.
    @Test func thePeekIsStateOfTheView() throws {
        #expect(try Self.row(contains: "@State private var peek: PrimaryWindow?"), """
            the peek is no longer view-local `@State` — held anywhere else it \
            would outlive the window, and the next opening would not show what \
            the Primary window setting says
            """)
    }

    /// The reset is what "not remembered" means in a popover that is cached:
    /// the SwiftUI tree survives between openings, so forgetting is explicit.
    @Test func closingTheWindowForgetsThePeek() throws {
        #expect(try Self.row(contains: "onDisappear { peek = nil }"), """
            the row no longer clears the peek when the window closes — the \
            popover is cached, so without this line a peek would be remembered \
            by accident and reopening would not show the default
            """)
    }

    /// The peek outranks the setting only while it exists.
    @Test func theRowResolvesThePeekOverTheSetting() throws {
        #expect(try Self.row(contains: "headlineWindow(for: peek ?? choice)"), """
            the row no longer resolves its window through `peek ?? choice` — \
            either the click shows nothing, or the setting stopped being the \
            default
            """)
    }

    /// A button that changes nothing is a broken button, so a one-window
    /// account keeps its plain text.
    @Test func onlyARowWithTwoPeriodsGetsTheButton() throws {
        #expect(try Self.row(contains: "hasAnotherPeriod"), """
            the row no longer asks whether there is another period before \
            drawing the button — a Codex account with one window would get a \
            click that does nothing
            """)
    }

    /// Nothing writes the peek anywhere. The negative half of "not stored".
    @Test func thePeekReachesNoStore() throws {
        for forbidden in ["UserDefaults", "PreferencesStore"] {
            #expect(try !Self.row(contains: forbidden), """
                the row now mentions \(forbidden) — the peek is designed to be \
                stored nowhere, and the row had no business with a store before
                """)
        }
    }

    private static func row(contains phrase: String) throws -> Bool {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // …/Tests/StatusUITests
            .deletingLastPathComponent()      // …/Tests
            .deletingLastPathComponent()      // …/Core
            .appendingPathComponent("Sources/StatusUI/MinimalAccountRow.swift")
        return try String(contentsOf: url, encoding: .utf8).contains(phrase)
    }
}
