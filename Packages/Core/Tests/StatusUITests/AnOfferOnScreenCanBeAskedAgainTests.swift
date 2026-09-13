import Testing
import Foundation

/// The Updates screen shows an answer, and an answer has a moment attached to
/// it. For most of one day it showed the wrong one: the daily check had run at
/// 09:57 UTC and found 0.1.3, seven more releases were published that day, and
/// the screen went on offering the first of them with no way to ask again.
///
/// The screen asking for itself is what fixed that, and it made `UpdateModel` a
/// path with two callers where it had been written for one. Most of what is
/// checked here is that second half: a check nobody asked for has to be able to
/// arrive without taking anything away.
///
/// Read out of the source rather than exercised: `UpdateModel` reads
/// `Bundle.main` and `UpdatesPane` is a view, and the package tests are the only
/// tests this project has. A scan cannot prove the screen behaves; it can prove
/// the claim is still written. Each assertion below is therefore phrased against
/// a slice of one declaration, never the whole file — a first version of this
/// suite asked whether `.available` appeared anywhere in `report()` and stayed
/// green against a mutant that did the exact opposite, because the word was
/// still in the comment.
///
/// This is code and not prose, so it is asked with `contains`: `checkIfStale`
/// reworded is a different function, not the same one rephrased. The phrase is
/// the only sub-expression an expectation here can print, for the reason
/// `HowToAskADocument` gives.
@Suite struct AnOfferOnScreenCanBeAskedAgain {

    /// Not "when it opens" — while it is open.
    ///
    /// The window that offered 0.1.3 all evening was open all evening. A check
    /// on appear alone would have left that complaint standing for the person
    /// who leaves the screen up waiting for a release, which is the person who
    /// had it.
    @Test func theScreenKeepsAskingWhileItIsOpen() throws {
        #expect(try Self.task(names: "await updates.checkIfStale("), """
            the Updates screen no longer asks from its .task — a call anywhere \
            else in the view body runs on redraws, and a screen that asks \
            nowhere shows whatever the last check found, a day ago
            """)

        #expect(try Self.task(names: "while !Task.isCancelled"), """
            the screen asks once and then stops — a settings window left open on \
            this pane goes back to reading out an answer that ages while \
            somebody watches it
            """)
    }

    /// The button existed. It was written into three of the five states the
    /// screen can be in, and the two it was left out of are the two where the
    /// screen makes a claim about the present: an offer, and a failure. The
    /// failure had one. The offer did not, so the one state that shows a version
    /// number was the one state that could not be corrected.
    @Test func anOfferOnScreenStillOffersAcheck() throws {
        #expect(try Self.offer(names: "checkButton"), """
            the screen offers a version and no way to ask whether it is still the \
            newest one — this is how 0.1.3 stayed on screen for seven releases
            """)
    }

    /// A check nobody asked for may improve the screen and may never weaken it.
    ///
    /// Every sentence this app shows is an answer of some strength — a version
    /// to install, "This is the latest version.", "No new version has been
    /// found." — and a quiet check arriving at a weaker one is not news, it is a
    /// screen changing by itself while somebody reads it.
    ///
    /// Both halves are checked because the first fix only did the failure. The
    /// success path weakens things too: `ReleaseFeed` maps a 404 to "nothing
    /// newer", and `UpdateModel`'s own comment says a 404 is ambiguous — a
    /// release mid-publish reads the same as a repository this caller cannot
    /// see.
    @Test func aQuietCheckNeverWeakensTheScreen() throws {
        #expect(try Self.reporting(names: "guard announcing else { return }"), """
            a failed quiet check writes the screen — the first version of this \
            guard named `.available` alone, which let a dropped connection \
            replace an honest "GitHub could not be reached" with the confident \
            false claim that it had been
            """)

        #expect(try !Self.reporting(names: "state = .idle"), """
            a failed quiet check still falls through to idle for some state — \
            there is no state where "No new version has been found." is the \
            right thing to learn from a request that never arrived
            """)

        // Asked for the state and not for one spelling of assigning it: the
        // first version of this line looked for `state = .idle` and stayed
        // green against `state = announcing ? .upToDate : .idle`, which is the
        // bug exactly.
        #expect(try !Self.settling(names: ".idle"), """
            a quiet check that finds nothing still writes idle — on a 404 that \
            takes a real offer off the screen, and `recordCheck` has already \
            stamped the moment, so neither schedule will ask again to correct it
            """)
    }

    /// Navigating away is not an outage.
    ///
    /// SwiftUI cancels a `.task` when its view goes, `URLSession` turns that
    /// into `URLError -999`, and one door down it is indistinguishable from a
    /// dropped connection. Without this, leaving the pane quickly logs an error
    /// and posts a report to the author — scaling with how often people click,
    /// not with how often anything is wrong. `PollScheduler` carries a comment
    /// about this exact mistake, made once already against the accounts list.
    @Test func acancelledCheckIsNotAFailure() throws {
        #expect(try Self.reporting(names: "Task.isCancelled"), """
            a cancelled request is reported as a failure again — switching away \
            from the Updates pane manufactures error reports and rewrites the \
            screen on the way out
            """)
    }

    /// One request out at a time.
    ///
    /// A quiet check never sets `.checking`, so it was invisible to the only
    /// guard the model had: one click on the menu item opened the window — whose
    /// pane asks — and then asked again beside it. Two answers then raced onto
    /// the screen, and two moments were stamped, either of which could be the
    /// one that stuck.
    @Test func oneRequestIsOutAtATime() throws {
        #expect(try Self.checking(names: "guard !inFlight"), """
            nothing holds a token for a request in flight — opening the update \
            screen from the menu sends two, and the later answer overwrites the \
            earlier one whichever was right
            """)
    }

    /// The switch is read in one place, and every quiet check goes through it.
    ///
    /// This is the claim with a privacy consequence: the caption under the
    /// toggle and the update paragraph on the privacy page both say, in ten
    /// languages, that nothing is asked when it is off. It held up on a `guard`
    /// that had been copied once already the day a second quiet check was added.
    /// A third entry point copies it a third time, and the one that forgets
    /// reaches GitHub for somebody who turned this off.
    @Test func everyQuietCheckReadsTheSwitchThroughOneGate() throws {
        let gates = try Self.timesModelNames("preferences.checksForUpdates")
        #expect(gates == 1, """
            the update switch is read in \(gates) places rather than one — each \
            copy is a promise made in ten languages resting on somebody \
            remembering to write the line again
            """)

        for schedule in ["isDue", "isStale"] {
            #expect(try Self.model(names: "checkQuietly(now: now, when: UpdateSchedule.\(schedule))"),
                    """
                    the \(schedule) check no longer routes through the gate that \
                    reads the switch — it either asks with automatic checking \
                    off, or it reads the switch from a second copy
                    """)
        }
    }

    // MARK: - each place, asked for a phrase and nothing else

    private static func task(names phrase: String) throws -> Bool {
        try body(of: ".task {", upTo: "// MARK:", in: read(paneFile)).contains(phrase)
    }

    private static func offer(names phrase: String) throws -> Bool {
        try body(of: "case .available(let release):", upTo: "case .installing",
                 in: read(paneFile)).contains(phrase)
    }

    private static func reporting(names phrase: String) throws -> Bool {
        try body(of: "private func report(", upTo: "// MARK:",
                 in: read(modelFile)).contains(phrase)
    }

    private static func settling(names phrase: String) throws -> Bool {
        try body(of: "private func settle(", upTo: "// MARK:",
                 in: read(modelFile)).contains(phrase)
    }

    private static func checking(names phrase: String) throws -> Bool {
        try body(of: "private func check(now: Date, announcing: Bool)", upTo: "// MARK:",
                 in: read(modelFile)).contains(phrase)
    }

    private static func model(names phrase: String) throws -> Bool {
        try read(modelFile).contains(phrase)
    }

    private static func timesModelNames(_ phrase: String) throws -> Int {
        try read(modelFile).components(separatedBy: phrase).count - 1
    }

    // MARK: -

    private static func read(_ file: URL) throws -> String {
        let text = try String(contentsOf: file, encoding: .utf8)
        guard text.count >= 1000 else {
            throw ScanIsLookingInTheWrongPlace(
                what: "\(file.lastPathComponent) source", found: text.count, least: 1000)
        }
        return text
    }

    /// The lines from `marker` up to whichever comes first of `upTo` and the
    /// next declaration. A slice that silently ran to the end of the file would
    /// approve the phrase anywhere in it, which is most of the way to approving
    /// nothing at all.
    private static func body(
        of marker: String, upTo terminator: String, in source: String
    ) throws -> String {
        guard let start = source.range(of: marker) else {
            throw ScanIsLookingInTheWrongPlace(what: "\(marker) in the source",
                                               found: 0, least: 1)
        }
        let rest = source[start.upperBound...]
        let end = [terminator, "\n    private func ", "\n    func ", "\n    var "]
            .compactMap { rest.range(of: $0)?.lowerBound }
            .min() ?? rest.endIndex

        let slice = String(rest[..<end])
        guard slice.count >= 40 else {
            throw ScanIsLookingInTheWrongPlace(what: "the body after \(marker)",
                                               found: slice.count, least: 40)
        }
        return slice
    }

    private static var paneFile: URL {
        repositoryRoot.appendingPathComponent("App/Settings/UpdatesPane.swift")
    }

    private static var modelFile: URL {
        repositoryRoot.appendingPathComponent("App/UpdateModel.swift")
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)      // …/Packages/Core/Tests/StatusUITests/<file>.swift
            .deletingLastPathComponent()      // …/Tests/StatusUITests
            .deletingLastPathComponent()      // …/Tests
            .deletingLastPathComponent()      // …/Core
            .deletingLastPathComponent()      // …/Packages
            .deletingLastPathComponent()      // repository root
    }
}
