import Testing
import Foundation

/// The Updates screen shows an answer, and an answer has a moment attached to
/// it. For most of one day it showed the wrong one: the daily check had run at
/// 09:57 UTC and found 0.1.3, seven more releases were published that day, and
/// the screen went on offering the first of them with no way to ask again.
///
/// Three things had to hold at once for that, and each is checked here.
///
/// Read out of the source rather than exercised: `UpdateModel` reads
/// `Bundle.main` and `UpdatesPane` is a view, and the package tests are the only
/// tests this project has. A scan cannot prove the screen behaves; it can prove
/// the call is still written, which is the part that was missing.
///
/// This is code and not prose, so it is asked with `contains`: `checkIfStale`
/// reworded is a different function, not the same one rephrased. The phrase is
/// the only sub-expression an expectation here can print, for the reason
/// `HowToAskADocument` gives.
@Suite struct AnOfferOnScreenCanBeAskedAgain {

    /// Opening the screen is somebody asking. It answered from cache.
    @Test func theScreenAsksAgainWhenItOpens() throws {
        #expect(try Self.pane(names: "checkIfStale"), """
            the Updates screen no longer asks again when it opens — it shows \
            whatever the last check found, and the last check can be a day old
            """)

        // The call has to be attached to the screen appearing. Written loose in
        // the body it would run on every redraw, which SwiftUI does often and
        // for reasons that have nothing to do with somebody looking.
        #expect(try Self.pane(names: ".task {"), """
            the Updates screen names checkIfStale but not from .task — a call in \
            the view body runs on redraws, not on the screen being opened
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

    /// Asking again has to be safe for what is already on screen.
    ///
    /// A check nobody announced puts its failure in the log and sets the screen
    /// to idle — which, once the screen started asking again by itself, would
    /// take a real offer away and replace it with "No new version has been
    /// found." on nothing more than a dropped connection. The quiet path has to
    /// look at what it is about to overwrite.
    @Test func aQuietFailureLeavesTheOfferOnScreen() throws {
        #expect(try Self.reporting(names: ".available"), """
            a failed quiet check sets the screen without reading what is on it — \
            an offer found this morning disappears the first time the network \
            blinks, and the screen says nothing was found
            """)
    }

    // MARK: - the three places, each asked for a phrase and nothing else

    private static func pane(names phrase: String) throws -> Bool {
        try read(paneFile).contains(phrase)
    }

    private static func offer(names phrase: String) throws -> Bool {
        try body(of: "case .available(let release):", upTo: "case .installing",
                 in: read(paneFile)).contains(phrase)
    }

    private static func reporting(names phrase: String) throws -> Bool {
        try body(of: "private func report(", upTo: "// MARK:",
                 in: read(modelFile)).contains(phrase)
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
    /// approve a `checkButton` anywhere in it.
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
