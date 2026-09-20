import Testing
import Foundation

/// The App Store copy of the app is told when a newer version exists.
///
/// It was not. The store build hid the Updates screen, left the menu item and
/// the footer button out, and never started the daily check, on the reasoning
/// that the store updates that copy. The store does — and it will not update an
/// app that is running, and a menu bar app is never not running. So the person
/// who installed from the store ran whatever they installed until they
/// happened to quit it, and nothing in the app said a word.
///
/// The three things that made it silent are each a single line that would be
/// easy to put back with the same reasoning, so they are read here. The
/// package cannot build `App/`, which is why these are scans and not runs.
@Suite struct TheStoreCopyIsToldAboutUpdates {

    @Test func theUpdatesScreenIsNotHiddenFromTheStoreBuild() throws {
        let settings = try Self.app("Settings/SettingsView.swift")
        #expect(!settings.contains("!= .updates"), """
            SettingsView filters the Updates section out again — the store copy \
            needs it to say where the newer version is
            """)
    }

    @Test func theDailyCheckStartsInBothLanes() throws {
        let launch = try Self.app("SoftcapApp.swift")
        guard let start = launch.range(of: "updates.startChecking()") else {
            Issue.record("SoftcapApp no longer starts the daily check at all")
            return
        }
        let before = launch[..<start.lowerBound].suffix(200)
        #expect(!before.contains("#if !APPSTORE"), """
            startChecking() is compiled out of the store build again — the copy \
            the store never updates while it runs is the copy that has to ask
            """)
    }

    @Test func theStoreCopyAsksTheStoreAndSendsPeopleThere() throws {
        let model = try Self.app("UpdateModel.swift")
        #expect(model.contains("case .appStore:") && model.contains("StoreListing.update("), """
            UpdateModel no longer reads the App Store's record in the store lane
            """)
        let pane = try Self.app("Settings/UpdatesPane.swift")
        #expect(pane.contains("Open the App Store") && pane.contains("updates.pageToOpen"), """
            the store lane's Updates screen has no button that opens the store
            """)
        // The store copy must never offer to install: the sandbox forbids it and
        // review would refuse it. The install call is behind the channel.
        #expect(model.contains("guard Self.channel == .github else { return }"), """
            install() is no longer refused in the store lane
            """)
    }

    private static func app(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent("App/\(path)"), encoding: .utf8)
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
