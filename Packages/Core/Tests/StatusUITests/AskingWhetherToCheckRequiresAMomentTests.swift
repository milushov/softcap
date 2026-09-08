import Testing
import Foundation

/// `now` is a required argument, and this is what keeps it one.
///
/// `ThresholdTracker.events(for:)` defaulted its moment to the system clock. A
/// test written before midnight set quiet hours of 1:00 to 2:00, passed all
/// evening, was committed green and pushed — and failed once one in the morning
/// arrived, with nothing changed. Green-then-red with no diff is worse than a
/// test that fails honestly, because there is nothing to read.
///
/// The compiler cannot help: adding a default back is source-compatible, every
/// call site keeps building, and the trap is reopened silently. So the source is
/// read instead.
@Suite struct AskingWhetherToCheckRequiresAMoment {

    @Test func theScheduleTakesTheMomentItIsAskedAbout() throws {
        let source = try String(contentsOf: Self.scheduleFile, encoding: .utf8)

        guard source.contains("isDue(") else {
            throw ScanIsLookingInTheWrongPlace(what: "isDue declaration", found: 0, least: 1)
        }

        // Any default at all, whichever way it is spelled.
        let defaulted = ["now: Date = ", "now: Date=", "now:Date="]
            .filter { source.contains($0) }

        #expect(defaulted.isEmpty, """
            UpdateSchedule defaults its moment to the clock again — the caller has to \
            say which moment it means, or a test written at one time of day fails at \
            another with nothing changed
            """)
    }

    private static var scheduleFile: URL {
        repositoryRoot
            .appendingPathComponent("Packages/Core/Sources/Updates/UpdateSchedule.swift")
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
