import Testing
import Foundation

/// A grouped `Form` insets its rows by twenty points of its own, on top of the
/// padding the detail area already applies. Two of the nine settings screens
/// are built without one, and their content sat directly under the screen's
/// heading; the other seven were indented from it by that twenty.
///
/// Nobody notices one screen at a time. It is obvious the moment two are
/// compared, and it was noticed that way.
///
/// The compiler cannot see this: a screen that forgets `alignedWithTheHeading()`
/// builds, runs and looks almost right. So the sources are read instead.
@Suite struct EveryScreenLinesUpWithItsHeading {

    @Test func everyGroupedFormCancelsTheInsetItAdds() throws {
        let panes = try Self.paneFiles()
        guard panes.count >= 8 else {
            throw ScanIsLookingInTheWrongPlace(what: "settings screen", found: panes.count, least: 8)
        }

        var grouped = 0
        var offenders: [String] = []
        for url in panes {
            let text = try String(contentsOf: url, encoding: .utf8)
            guard text.contains("formStyle(.grouped)") else { continue }
            grouped += 1
            if !text.contains("alignedWithTheHeading()") {
                offenders.append(url.lastPathComponent)
            }
        }

        // Vacuous otherwise: a scan that finds no grouped form approves them all.
        guard grouped >= 5 else {
            throw ScanIsLookingInTheWrongPlace(what: "grouped form", found: grouped, least: 5)
        }

        #expect(offenders.isEmpty, """
            \(offenders.sorted().joined(separator: ", ")) builds a grouped form and does not \
            cancel the inset it adds, so its content sits indented from its own heading while \
            the screens built without a form do not
            """)
    }

    /// The other half: the modifier has to still exist, and to still be the
    /// cancellation rather than something that happens to be named that.
    @Test func theModifierCancelsRatherThanAdds() throws {
        let text = try String(contentsOf: Self.settingsView, encoding: .utf8)
        #expect(text.contains("func alignedWithTheHeading()"),
                "the modifier every screen calls is gone")
        #expect(text.contains("padding(.horizontal, -groupedFormInset)"), """
            alignedWithTheHeading no longer subtracts the form's inset — the screens \
            all call it and it would be quietly doing nothing
            """)
    }

    private static func paneFiles() throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: repositoryRoot.appendingPathComponent("App/Settings"),
                                 includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix("Pane.swift") }
    }

    private static var settingsView: URL {
        repositoryRoot.appendingPathComponent("App/Settings/SettingsView.swift")
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
