import Testing
import Foundation
@testable import StatusUI

/// The mark on the account in use costs the rows around it nothing.
///
/// In the minimal window the mark sits at the leading edge, because the other
/// end of that line is three columns measured to the widest word in ten
/// languages and nothing may be inserted there. A leading mark drawn on one row
/// alone would push that row's name to the right of its neighbours' — the
/// raggedness those columns were measured to remove, reintroduced at the other
/// end of the same line.
///
/// So the room is reserved on every row as soon as any row has it, and the
/// unmarked ones draw the dot invisible rather than not drawing it. That is one
/// character's difference in the source — `if let inUse` against
/// `if inUse == true` — and it is invisible in a screenshot until two accounts
/// are signed in and one of them is being used, which is why it is written down
/// here instead.
@Suite struct TheMarkedRowDoesNotMoveItsNeighbours {

    private static var minimalRow: String {
        get throws {
            try String(
                contentsOf: repositoryRoot.appendingPathComponent(
                    "Packages/Core/Sources/StatusUI/MinimalAccountRow.swift"),
                encoding: .utf8)
        }
    }

    @Test func theMinimalRowReservesTheRoomOnEveryRow() throws {
        let text = try Self.minimalRow

        #expect(text.contains("if let inUse {"), """
            the minimal row no longer reserves the mark's room on unmarked \
            rows. Drawn only where the mark is, it indents one name past the \
            others.
            """)
        #expect(text.contains(".opacity(inUse ? 1 : 0)"), """
            the reserved room no longer holds an invisible dot — reserving it \
            and then drawing nothing is the same as not reserving it
            """)
        #expect(text.contains(".frame(width: InUseDot.size)"), """
            the reserved room is not the dot's own width, so a marked row and \
            an unmarked one are indented differently
            """)
    }

    /// And the full row, which has loose space at its trailing end, does not
    /// reserve anything — there is nothing there to line up against.
    @Test func theFullRowDrawsTheMarkOnlyWhereItIs() throws {
        let text = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(
                "Packages/Core/Sources/StatusUI/AccountRow.swift"),
            encoding: .utf8)
        #expect(text.contains("if inUse == true { InUseDot() }"))
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
