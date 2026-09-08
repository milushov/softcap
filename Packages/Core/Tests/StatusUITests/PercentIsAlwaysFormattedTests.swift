import Testing
import Foundation
@testable import StatusUI

/// A percentage is spelled by `Localization.percent(_:)`, never by putting a `%`
/// after a number.
///
/// Four of the ten languages disagree with `"\(n)%"`: Russian, French and Spanish
/// separate the sign with a non-breaking space, Arabic wraps it in directional
/// marks. That was fixed everywhere once — and then the iPhone widget was found
/// still doing it by hand, months of edits later, because nothing was watching.
///
/// The pattern is a `%` immediately after a closing interpolation. Format
/// specifiers — `%@`, `%lld`, `%1$@` — never look like that, so they pass.
@Suite struct PercentIsAlwaysFormatted {

    /// The one file allowed to write the sign: it is the one that decides where
    /// the sign goes.
    private static let allowed = ["Formatting.swift"]

    @Test func nowhereBuildsAPercentageByHand() throws {
        var offenders: [String] = []
        for url in try Self.sources() where !Self.allowed.contains(url.lastPathComponent) {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (number, line) in text.components(separatedBy: "\n").enumerated()
            where line.contains(")%") {
                offenders.append("\(url.lastPathComponent):\(number + 1)")
            }
        }
        #expect(offenders.isEmpty, """
            a percentage spelled by hand at \(offenders.sorted()) — \
            use `loc.percent(_:)`, which four of the ten languages need
            """)
    }

    /// The same rule, in the place the Swift scan cannot see.
    ///
    /// A format string is not code — it is ten strings, and each one has to
    /// remember the rule on its own. Three did not: French and Spanish left out
    /// the space their languages require, Arabic the directional marks, Russian
    /// used an ordinary space where the locale uses a non-breaking one. The
    /// sign had been swept out of the code twice by then; nothing was reading
    /// the catalogues.
    ///
    /// So a catalogue may not contain the sign at all. The number arrives
    /// already spelled, as `%@`.
    @Test func noCatalogueSpellsTheSignItself() throws {
        var offenders: [String] = []
        for url in try Self.catalogues() {
            let text = try String(contentsOf: url, encoding: .utf8)
            let language = url.deletingLastPathComponent().lastPathComponent
            for (number, line) in text.components(separatedBy: "\n").enumerated() {
                guard let value = Self.value(ofEntryOn: line) else { continue }
                guard Self.stripSpecifiers(from: value).contains("%") else { continue }
                offenders.append("\(language):\(number + 1) — \(value)")
            }
        }
        #expect(offenders.isEmpty, """
            a catalogue spells the percent sign itself at \(offenders.sorted()) — \
            pass the share as `%@`, already spelled by `loc.percent(_:)`, so that \
            no catalogue has to know where its language puts the sign
            """)
    }

    /// The value of a `"key" = "value";` line, or nil if the line is not one.
    private static func value(ofEntryOn line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix("\";"), let equals = trimmed.range(of: "\" = \"")
        else { return nil }
        return String(trimmed[equals.upperBound...].dropLast(2))
    }

    /// Removes `%@`, `%lld`, `%1$@` and friends. Whatever `%` survives was
    /// written as a sign.
    private static func stripSpecifiers(from value: String) -> String {
        value.replacing(
            try! Regex("%(\\d+\\$)?(lld|ld|@|d|f)"), with: ""
        )
    }

    private static func catalogues() throws -> [URL] {
        let found = try walkcatalogues()
        guard found.count >= 10 else {
            throw ScanIsLookingInTheWrongPlace(what: "catalogue", found: found.count, least: 10)
        }
        return found
    }

    private static func walkcatalogues() throws -> [URL] {
        let root = repositoryRoot
            .appendingPathComponent("Packages/Core/Sources/StatusUI/Resources")
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { return [] }
        var found: [URL] = []
        for case let url as URL in walker where url.lastPathComponent == "Localizable.strings" {
            found.append(url)
        }
        return found
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

