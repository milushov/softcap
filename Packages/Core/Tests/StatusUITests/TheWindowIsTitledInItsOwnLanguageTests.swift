import Testing
import Foundation
@testable import StatusUI

/// The settings window's title is the app's to write.
///
/// macOS titles a `Settings` scene itself — `Softcap Settings`, `Réglages de
/// Softcap` — in the language the *system* is set to. This app does not take
/// its language from the system: it is chosen in its own settings, and every
/// other label follows that choice. The two disagreed on the title bar, and
/// three of the five store screenshots are of that window, so the disagreement
/// was published: a Russian interface under an English heading.
///
/// `SettingsWindow.retitle()` writes the title instead, and `applyLanguage()`
/// calls it — a window already open keeps whatever title it was given, so
/// writing it once when it opens leaves the old language on screen for exactly
/// the person who has just changed it.
@Suite struct TheWindowIsTitledInItsOwnLanguage {

    @MainActor
    @Test func theTitleIsSpelledInEachLanguage() {
        let localization = Localization()
        var seen: Set<String> = []

        for language in AppLanguage.allCases where language != .system {
            localization.use(language)
            let title = localization.settingsWindowTitle("Softcap")
            #expect(title.contains("Softcap"), "\(language.rawValue): \(title) drops the name")
            #expect(!title.contains("%@"), "\(language.rawValue): \(title) keeps its placeholder")
            seen.insert(title)
        }

        // Ten languages, ten catalogues: several may legitimately arrive at the
        // same words, but not all of them — that would mean the key is missing
        // everywhere and the English is being echoed back.
        #expect(seen.count >= 6, "the title is the same in every language: \(seen.sorted())")
    }

    /// The wiring, in the place a unit test cannot reach: `App` is not built by
    /// the package, so the call is read rather than run.
    @Test func changingTheLanguageRewritesTheTitle() throws {
        let model = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent("App/PreferencesModel.swift"),
            encoding: .utf8)
        guard let apply = model.range(of: "private func applyLanguage()") else {
            Issue.record("PreferencesModel no longer applies the language in applyLanguage()")
            return
        }
        let body = model[apply.upperBound...].prefix(400)
        #expect(body.contains("SettingsWindow.retitle()"), """
            applyLanguage() no longer retitles the settings window — a window \
            left open keeps the title of the language it was opened in
            """)
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
