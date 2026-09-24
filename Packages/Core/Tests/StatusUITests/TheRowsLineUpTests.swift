import Testing
import Foundation

/// The minimal window is four short lines meant to be read at a glance, and a
/// glance reads down as well as across. Its three right-hand values are
/// columns: the period, the percentage, the time left.
///
/// They were not. The percentage is three digits at a hundred and two below
/// it, so the period label beside it sat a digit further left in whichever row
/// happened to be full — visible in every screenshot the store ever got.
///
/// Each column is sized by drawing the widest thing it can hold hidden
/// underneath it. The alternative was a number of points, which is a
/// measurement of one language: `5h` and `week` in English are `5ч` and `нед`
/// in Russian and neither pair is the same width.
///
/// "The widest thing it can hold" is the part that goes stale. It was two words
/// while there were two window kinds, and a third arrived measuring nothing —
/// so the identifiers are listed here as well as in the view, and a provider
/// that starts producing a fourth fails this rather than shipping one ragged
/// row among aligned ones.
///
/// Scanned out of the source for the reason `ThePeekIsNotRemembered` gives:
/// these are views, and a scan cannot prove a window lines up — it can prove
/// the thing that makes it line up is still written.
@Suite struct TheRowsLineUp {

    @Test func thePeriodColumnIsAsWideAsItsLongestWord() throws {
        let row = try Self.row()
        #expect(row.contains("widestPeriod.hidden()"), """
            the period column is no longer sized by the longer of its two \
            words — the label goes back to sitting wherever the percentage \
            beside it leaves room, which differs by a digit from row to row
            """)
        // Every identifier a provider produces. A kind missing here is a row
        // that measures narrower than the word it draws.
        for id in ["session", "weekly", "premium"] {
            // The call the hidden copy makes, not the text it contains: written
            // as `Text(loc.windowTitle(…))` this passed on `periodText(…)` as a
            // substring, which is the drift it was meant to catch.
            #expect(row.contains("periodText(loc.windowTitle(\"\(id)\"))"), """
                the sizing no longer measures the \(id) word through the same \
                helper the label uses, so a font changed in one place measures \
                the column at the other's size
                """)
        }
        // Inside `widestPeriod`, not anywhere in the file: the unclickable
        // branch carries the same call, so a check for the bare string passed
        // with the measuring copy stripped of it. Found by breaking it.
        #expect(try Self.body(of: "private var widestPeriod").contains(
            ".padded(by: Self.periodInset)"), """
            the hidden copy is no longer padded the way the button pads its \
            word — the column is then measured without the room the chip takes, \
            and the clickable rows sit a chip's width off the rest
            """)
    }

    @Test func thePercentageColumnIsAsWideAsAHundred() throws {
        let row = try Self.row()
        #expect(row.contains("percentText(loc.percent(100)).hidden()"), """
            the percentage column is no longer sized by the widest percentage \
            there is — at a hundred it grows a digit and pushes the period \
            label sideways, which is the fault this was written for
            """)
    }

    /// Trailing, and nothing else. A column measured to the widest and then
    /// filled from the left would line up its left edges and leave the digits
    /// ragged, which for a number is the wrong edge.
    @Test func bothColumnsAreFilledFromTheRight() throws {
        let row = try Self.row()
        // At least the two, rather than exactly them: a third measured column
        // would be somebody adding to this, and turning one of the two back to
        // leading is what this watches for — that drops the count to one.
        #expect(row.components(separatedBy: "ZStack(alignment: .trailing)").count - 1 >= 2, """
            the two measured columns are no longer both trailing-aligned — a \
            number lines up on its last digit, not its first
            """)
    }

    /// The column that was already fixed, and the comment that says why. It is
    /// the reason the percentage's right edge never moved, and the reason the
    /// fault was only ever visible one column further left.
    @Test func theTimeLeftKeepsTheWidthItAlreadyHad() throws {
        #expect(try Self.row().contains(".frame(width: 58, alignment: .trailing)"), """
            the time column lost its fixed width — the countdown changes unit \
            as it runs, and everything left of it would shuffle every time
            """)
    }

    /// Nothing drawn to be measured is drawn to be read. The row collapses
    /// into one spoken sentence, so a hidden copy of a word is not a word
    /// VoiceOver meets twice — but only while that line is there.
    @Test func theMeasuringCopiesAreNotSpoken() throws {
        #expect(try Self.row().contains(".accessibilityElement(children: .ignore)"), """
            the row no longer collapses into a single spoken element, so the \
            hidden copies that size the columns are now two words VoiceOver \
            reads on its way through the row
            """)
    }

    /// One declaration out of the row, from its opening line to the closing
    /// brace at its own indentation.
    private static func body(of declaration: String) throws -> String {
        let row = try Self.row()
        guard let start = row.range(of: declaration) else {
            throw ScanIsLookingInTheWrongPlace(what: declaration, found: 0, least: 1)
        }
        let rest = row[start.upperBound...]
        guard let end = rest.range(of: "\n    }") else {
            throw ScanIsLookingInTheWrongPlace(what: declaration + " body", found: 0, least: 1)
        }
        return String(rest[..<end.lowerBound])
    }

    private static func row() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // …/Tests/StatusUITests
            .deletingLastPathComponent()      // …/Tests
            .deletingLastPathComponent()      // …/Core
            .appendingPathComponent("Sources/StatusUI/MinimalAccountRow.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        guard text.count >= 5_000 else {
            throw ScanIsLookingInTheWrongPlace(
                what: "MinimalAccountRow", found: text.count, least: 5_000)
        }
        return text
    }
}
