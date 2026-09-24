import Testing
import Foundation

/// A period label says what its window is, not what its author assumed.
///
/// The compact layout wrote `loc.windowTitle("weekly")` beside a value it had
/// found with `first { $0.id == "weekly" } ?? windows.first` — a fallback whose
/// whole purpose is to hand back something that is *not* the weekly window. For
/// two services that could not go wrong, because both reported a weekly window
/// and the fallback never fired. For a service reporting one monthly allowance
/// it fired every time, and the row read `week 42%` about a month: the app
/// stating the wrong period about the one number it exists to report.
///
/// Nothing else would have caught it. It is a label, not a behaviour; the
/// number beside it was right; and the two other layouts in the same file did
/// it correctly, so a reader comparing them would see three similar lines and
/// no contradiction.
///
/// So the rule is written down: where a window is drawn, its title is asked for
/// by identifier. The one place allowed to name identifiers is the hidden stack
/// that *measures* the column, which draws every one of them on purpose and is
/// held to that by `TheRowsLineUp`.
@Suite struct APeriodLabelReadsItsWindow {

    /// Files that draw a window's label for a window they have in hand, each
    /// with the accessor it asks through. The two spellings differ by a capital
    /// letter, and checking for the wrong one is how this test first passed
    /// while guarding nothing.
    private static let drawing = [
        ("Packages/Core/Sources/StatusUI/AccountRow.swift", "windowTitle("),
        ("Packages/Core/Sources/StatusUI/Accessibility.swift", "spokenWindowTitle("),
    ]

    @Test func noLabelNamesItsPeriodWithALiteral() throws {
        for (path, accessor) in Self.drawing {
            let file = Self.repositoryRoot.appendingPathComponent(path)
            let text = try String(contentsOf: file, encoding: .utf8)

            // Vacuous otherwise: a file that stopped asking at all would pass a
            // check for the wrong way of asking.
            #expect(text.contains(accessor), """
                \(path) no longer calls \(accessor)…). If the label moved, this \
                check has to move with it or it is guarding nothing.
                """)

            #expect(!text.contains(accessor + "\""), """
                \(path) writes \(accessor)"…") — a period named from a literal \
                rather than read from the window beside it. That is how the \
                compact row came to call a monthly allowance "week".
                """)
        }
    }

    /// And the measuring stack, which is the exception, still is one.
    @Test func onlyTheMeasuringStackNamesThem() throws {
        let text = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(
                "Packages/Core/Sources/StatusUI/MinimalAccountRow.swift"),
            encoding: .utf8)

        // Drawn to be measured, never seen. Every identifier belongs here; the
        // label beside it must still come from the window.
        for id in ["session", "weekly", "premium"] {
            #expect(text.contains("periodText(loc.windowTitle(\"\(id)\"))"))
        }
        #expect(text.contains("periodText(loc.windowTitle(window.id))")
                || text.contains("loc.windowTitle(window.id)"), """
            the minimal row's visible label no longer reads its own window
            """)
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
