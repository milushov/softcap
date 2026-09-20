import Testing
import Foundation
@testable import StatusUI

/// A date SwiftUI spells for us takes its language from the format style it is
/// given, not from the environment around it.
///
/// `SettingsView` and `PopoverView` both set `\.locale` to the chosen language,
/// and `LanguageShapesBothDirectionAndFormat` holds them to it. Swift Charts
/// does not read that: `AxisValueLabel(format:)` formats with the system's
/// locale whatever the environment says. It showed in the store screenshots —
/// the statistics chart spelled its days `14 Sep` under a Russian interface,
/// one line below a heading reading `Статистика`, and the same in nine other
/// languages.
///
/// This is the third appearance of one bug. `UpdatesPane` carries a comment
/// about the second ("the badge said `28 Aug` in one language and the clock
/// beside it read in another"), and the comment says the fix is to name the
/// locale outright rather than to hope it is inherited. So: every date the app
/// spells goes through a format style that names the language, and the scan
/// below is what notices the next one that does not.
@Suite struct DatesFollowTheChosenLanguage {

    /// The three the chart has to get right: a Latin month that abbreviates
    /// differently, a language that does not use Latin letters at all, and a
    /// language whose digits are its own.
    @MainActor
    @Test func theChartSpellsItsDaysInTheChosenLanguage() {
        let localization = Localization()
        // 14 September 2026, 12:00 UTC — a day and a month that are spelled
        // differently in each of the three, and far from a month boundary so no
        // time zone can move it.
        let day = Date(timeIntervalSince1970: 1_789_387_200)

        localization.use(.english)
        let english = day.formatted(localization.chartDay)
        localization.use(.russian)
        let russian = day.formatted(localization.chartDay)
        localization.use(.arabic)
        let arabic = day.formatted(localization.chartDay)

        #expect(english.contains("Sep"), "English chart axis: \(english)")
        #expect(russian.contains("сент"), "Russian chart axis: \(russian)")
        #expect(russian != english, "the chart spells its days in one language for all ten")
        #expect(arabic != english, "Arabic chart axis: \(arabic)")
    }

    /// The general rule, in the place a behavioural test cannot reach: a format
    /// style written into a view is not called from a test, and the next one
    /// will be written into a view.
    @Test func noDateFormatIsLeftToTheSystemsLanguage() throws {
        var offenders: [String] = []
        for url in try Self.sources() {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (number, line) in text.components(separatedBy: "\n").enumerated() {
                guard line.contains(".dateTime") || line.contains("Date.FormatStyle(") else { continue }
                guard !line.contains("locale") else { continue }
                offenders.append("\(url.lastPathComponent):\(number + 1)")
            }
        }
        #expect(offenders.isEmpty, """
            a date format that names no locale at \(offenders.sorted()) — it will \
            be spelled in the system's language while the labels around it follow \
            the app's; add `.locale(loc.activeLocale)`
            """)
    }

    /// `DateFormatter` is the older half of the same rule. Every one of them in
    /// the app sets `.locale` on the line after it is made; this is what says so.
    @Test func everyDateFormatterIsGivenALanguage() throws {
        var offenders: [String] = []
        for url in try Self.sources() {
            let text = try String(contentsOf: url, encoding: .utf8)
            let lines = text.components(separatedBy: "\n")
            for (number, line) in lines.enumerated() where line.contains("DateFormatter()") {
                let next = lines[(number + 1)..<min(number + 4, lines.count)]
                guard !next.contains(where: { $0.contains(".locale = ") }) else { continue }
                offenders.append("\(url.lastPathComponent):\(number + 1)")
            }
        }
        #expect(offenders.isEmpty, """
            a DateFormatter with no locale at \(offenders.sorted()) — set \
            `formatter.locale = loc.activeLocale` beside it
            """)
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
        guard found.count >= 20 else {
            throw ScanIsLookingInTheWrongPlace(what: "source", found: found.count, least: 20)
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
