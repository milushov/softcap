import Testing
import Foundation
@testable import StatusUI

/// A view that takes its writing direction from the chosen language must take
/// its number and date formatting from it too.
///
/// They are the same setting and they are forgotten separately. Every root view
/// set `layoutDirection` and none set `locale`, so SwiftUI wrote dates and times
/// in the system's language while the labels around them followed the app's —
/// the staleness badge reading `28 Aug` with a clock beside it in another
/// tongue. The percentages had already been fixed by hand; the dates had not,
/// because nothing paired them.
@Suite struct LanguageShapesBothDirectionAndFormat {

    @Test func everyViewThatSetsDirectionAlsoSetsLocale() throws {
        var offenders: [String] = []
        for url in try Self.sources() {
            let text = try String(contentsOf: url, encoding: .utf8)
            guard text.contains("layoutDirection, loc.layoutDirection") else { continue }
            if !text.contains("\\.locale, loc.activeLocale") {
                offenders.append(url.lastPathComponent)
            }
        }
        #expect(offenders.isEmpty, """
            takes its writing direction from the language and its formatting from \
            the system: \(offenders.sorted())
            """)
    }

    /// The rule above is conditional — a file that takes its direction from the
    /// language must take its formatting from there too — and a conditional rule
    /// is defeated by removing the condition. Writing `.rightToLeft` straight
    /// into a view makes it stop applying, and the view then has a direction
    /// nobody chose and a locale nobody set.
    ///
    /// Found while trying to break the rule above and failing: the mutation took
    /// out the trigger rather than the property, and the guard fell silent
    /// exactly as it would for the real mistake.
    @Test func nothingButTheChartWritesADirectionIn() throws {
        var offenders: [String] = []
        var examined = 0
        for url in try Self.sources() {
            examined += 1
            guard url.lastPathComponent != "UsageChart.swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for literal in ["layoutDirection, .leftToRight", "layoutDirection, .rightToLeft"]
            where text.contains(literal) {
                offenders.append("\(url.lastPathComponent): \(literal)")
            }
        }
        guard examined >= 20 else {
            throw ScanIsLookingInTheWrongPlace(what: "view source", found: examined, least: 20)
        }
        #expect(offenders.isEmpty, """
            a direction is written in rather than taken from the language: \
            \(offenders.sorted()) — the chart is the one place that is right, \
            because an axis is not text
            """)
    }

    /// The chart pins its direction on purpose — an axis is not text and a
    /// mirrored one reads a rising line as falling. That is not the same thing
    /// and must not be caught by the rule above.
    @Test func theChartMayPinItsDirectionWithoutPinningItsLanguage() throws {
        let chart = try String(
            contentsOf: Self.repositoryRoot
                .appendingPathComponent("Packages/Core/Sources/StatusUI/UsageChart.swift"),
            encoding: .utf8
        )
        #expect(chart.contains("layoutDirection, .leftToRight"),
                "the chart stopped pinning its direction")
        #expect(!chart.contains("layoutDirection, loc.layoutDirection"),
                "the chart is following the language's direction, which mirrors time")
    }

    private static func sources() throws -> [URL] {
        let roots = ["Packages/Core/Sources", "App", "Widget", "iOS", "iOSWidget"]
        var found: [URL] = []
        for name in roots {
            let root = repositoryRoot.appendingPathComponent(name)
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
            else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                found.append(url)
            }
        }
        return found
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
