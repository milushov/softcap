import Testing
import Foundation

/// A widget may count from `entry.date`; it may not present it as a time.
///
/// `entry.date` is the moment WidgetKit built the timeline entry — now. Counting
/// a reset down from it is right, because a countdown counts from now. Printing
/// it is not: the data came from a file the app wrote, whenever it last ran, and
/// both widgets showed the current clock beside percentages of any age. On a
/// sleeping Mac or a phone whose app has not been opened in a week, that is a
/// freshness the numbers do not have.
///
/// The reading time is `snapshot.capturedAt`, and past `readingAge`'s tolerance
/// the age replaces the clock — the vocabulary the window already uses.
@Suite struct AWidgetShowsWhenItWasRead {

    @Test func noWidgetPrintsTheTimeTheEntryWasBuilt() throws {
        var offenders: [String] = []
        for url in try Self.widgetSources() {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (number, line) in text.components(separatedBy: "\n").enumerated() {
                // The shape the bug took the first time: `Text(entry.date, style:)`.
                if line.contains("entry.date, style:") {
                    offenders.append("\(url.lastPathComponent):\(number + 1) prints it")
                }
                // And the rule behind it. Handing `entry.date` to `readingAge` as
                // the moment the figures were read gives the same wrong answer by
                // another road: a week-old reading measured against now is fresh,
                // and the widget shows a clock instead of an age. This guard
                // watched one syntax while the test below it says, in words, that
                // a guard shaped like the last bug is not enough.
                guard let marker = line.range(of: "lastUpdated:") else { continue }
                let argument = line[marker.upperBound...]
                    .prefix { $0 != "," && $0 != ")" }
                if !argument.contains("capturedAt") {
                    offenders.append("\(url.lastPathComponent):\(number + 1) ages against\(argument)")
                }
            }
        }
        #expect(offenders.isEmpty, """
            a widget prints entry.date at \(offenders.sorted()) — that is when the \
            timeline entry was built, not when the figures were read; show \
            snapshot.capturedAt, and its age once readingAge calls it overdue
            """)
    }

    /// The other half, and the rule rather than the shape of the last bug: a
    /// surface that shows figures has to be able to say how old they are.
    ///
    /// This began as "both widgets" and was widened the same week, because the
    /// phone's own screen turned out never to have shown its reading time at
    /// all — the model published `lastUpdated` and nothing read it. A guard
    /// written around the two places a bug had been found would have passed.
    @Test func everySurfaceThatShowsFiguresCanSayTheirAge() throws {
        for surface in ["App", "Widget", "iOS", "iOSWidget"] {
            let sources = try Self.widgetSources(under: surface)
            let asks = sources.contains { url in
                (try? String(contentsOf: url, encoding: .utf8))?.contains("readingAge(") ?? false
            }
            #expect(asks, "\(surface) never works out how old its reading is")
        }
    }

    /// A reading time with nothing read is a freshness claim about nothing.
    ///
    /// The phone sets `lastUpdated` after every poll, including one that found no
    /// accounts, and the screen showed it — a fresh simulator displayed the
    /// current time above "No accounts found", which reads as "these figures are
    /// current and there are none of them" rather than "nobody is signed in".
    /// The Mac window in the same state shows its two sentences and no time.
    ///
    /// Seen by running the app in a simulator and looking at it, which nothing
    /// else here does.
    @Test func thePhoneDatesAReadingOnlyWhenThereIsOne() throws {
        let screen = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent("iOS/LimitsScreen.swift"),
            encoding: .utf8)
        guard let start = screen.range(of: "private var freshness"),
              let body = screen.range(of: "if let updated",
                                      range: start.upperBound..<screen.endIndex) else {
            Issue.record("the phone screen no longer has a view for the reading's age")
            return
        }
        let condition = String(screen[body.lowerBound...].prefix(120))
        #expect(condition.contains("snapshots.isEmpty"), """
            the phone dates its reading without checking there is one, so an empty \
            screen carries the time of the poll that found nothing
            """)
    }

    private static func widgetSources(under name: String? = nil) throws -> [URL] {
        let found = try everyWidgetSource(under: name)
        guard found.count >= 2 else {
            throw ScanIsLookingInTheWrongPlace(what: "widget source", found: found.count, least: 2)
        }
        return found
    }

    private static func everyWidgetSource(under name: String? = nil) throws -> [URL] {
        var found: [URL] = []
        for directory in name.map({ [$0] }) ?? ["Widget", "iOSWidget"] {
            let root = repositoryRoot.appendingPathComponent(directory)
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
            else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                found.append(url)
            }
        }
        return found
    }

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
}

