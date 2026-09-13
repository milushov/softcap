import Testing
import Foundation

/// `ThresholdTracker` emits an event only on a crossing, which needs a reading
/// below the threshold and one above. That memory lived only in the process, and
/// two ordinary things erased it: relaunching the app, and changing any
/// notification setting.
///
/// The consequence was not a late warning but no warning at all. An account
/// already past 80% when the app came back has nothing below it to cross from,
/// and it stays above until the limit resets — so the promise on the landing,
/// "it tells you before you hit it", was not kept for that whole window.
///
/// `Monitoring` has the behavioural tests. This is the wiring, which lives in
/// `App/` where nothing else can reach it: two calls, either of which could be
/// deleted in a tidy-up without a single test going red.
@Suite struct TheTrackerRemembersAcrossLaunches {

    @Test func theBaselineIsCarriedWhenTheTrackerIsRebuilt() throws {
        let source = try Self.appModel()
        let rebuild = try Self.body(of: "private func rebuildTrackerIfNeeded", in: source)

        #expect(rebuild.contains("tracker.baseline"),
                "the rebuild does not take the outgoing tracker's baseline")
        #expect(rebuild.contains("tracker.restore("),
                "the rebuild does not hand the baseline to the new tracker")
    }

    @Test func theBaselineIsRestoredFromDiskAtStart() throws {
        let source = try Self.appModel()
        let start = try Self.body(of: "func start() async", in: source)
        #expect(start.contains("seedTrackerFromDisk()"),
                "nothing restores the baseline at launch, so a relaunch is a first run")

        let seeding = try Self.body(of: "private func seedTrackerFromDisk", in: source)
        // `readLocal`, not `read`: the shared copy lives in the app group
        // container, and reaching that at launch is what asked every reader for
        // permission to "access data from other apps" before anything was drawn.
        // The baseline is the app's own business and reads the app's own file.
        #expect(seeding.contains("SharedStore.readLocal()"),
                "the seed does not read the snapshot the last run left behind")
        #expect(!seeding.contains("SharedStore.read()"), """
            the seed reaches into the app group container at launch, which is the \
            prompt this was moved out of
            """)
        #expect(seeding.contains("capturedAt"), """
            the seed does not check how old the reading is; a transition from days ago would be announced as though it had just happened
            """)
    }

    /// A relaunch, not a return after an absence: the window has to stay short
    /// enough that nothing stale is resurrected.
    @Test func aStaleReadingIsNotUsedAsABaseline() throws {
        let source = try Self.appModel()
        guard let window = Self.firstGroup(
            #"baselineIsStaleAfter: TimeInterval = ([0-9]+) \* 60"#, in: source
        ).flatMap(Int.init) else {
            Issue.record("the staleness window is no longer written as minutes × 60")
            return
        }
        #expect(window <= 30, "\(window) minutes is long enough to announce old news")
        #expect(window >= 5, "\(window) minutes is short enough to miss an ordinary relaunch")
    }

    // MARK: -

    /// From a declaration to the matching closing brace, by counting braces.
    /// Searching the whole file would find `tracker.restore(` anywhere in it,
    /// including in the method next door.
    private static func body(of declaration: String, in source: String) throws -> String {
        guard let start = source.range(of: declaration),
              let open = source.range(of: "{", range: start.upperBound..<source.endIndex)
        else { throw ScanIsLookingInTheWrongPlace(what: declaration, found: 0, least: 1) }

        var depth = 0
        var index = open.lowerBound
        while index < source.endIndex {
            if source[index] == "{" { depth += 1 }
            if source[index] == "}" {
                depth -= 1
                if depth == 0 { return String(source[open.upperBound..<index]) }
            }
            index = source.index(after: index)
        }
        throw ScanIsLookingInTheWrongPlace(what: declaration + " (unclosed)", found: 0, least: 1)
    }

    private static func firstGroup(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func appModel() throws -> String {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("App/AppModel.swift"),
            encoding: .utf8)
        guard source.count > 5_000 else {
            throw ScanIsLookingInTheWrongPlace(what: "AppModel", found: source.count, least: 5_000)
        }
        return source
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
