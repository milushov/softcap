import Testing
import Foundation

/// The App Store copy carries no updater at all — no check, no screen, no menu
/// item, and no host to ask.
///
/// It carried one for four days. The store build read the App Store's own
/// lookup record once a day, said `Version 0.1.31 is on the App Store.` and
/// offered a button that opened the store, on the reasoning — written down on
/// 21 September and correct about the facts — that the store will not update an
/// app while it runs, and a menu bar app never stops running. App Review
/// rejected 0.1.36 for it on 24 September under guideline 2.4.5(vii), *"The app
/// updates itself outside of the Mac App Store"*: the guideline forbids the
/// check, not only the install, and being right about the inconvenience does
/// not make it allowed.
///
/// So the reasoning is settled and this file is what keeps it settled. Each
/// thing below is a single line somebody could put back with the 21 September
/// argument, which is a good argument and still gets the app rejected.
/// `docs/DECISIONS.md`, 2026-09-25, carries the whole of it.
///
/// The disk image is not touched: guideline 2.4.5 governs what the Mac App
/// Store ships, and the copy from GitHub keeps the full flow, install and all.
/// That is why these look for `#if !APPSTORE` rather than for the feature being
/// gone.
///
/// The package cannot build `App/`, which is why these are scans and not runs.
@Suite struct TheStoreCopyHasNoUpdater {

    @Test func theDailyCheckIsCompiledOutOfTheStoreBuild() throws {
        let launch = try Self.app("SoftcapApp.swift")
        guard let start = launch.range(of: "updates.startChecking()") else {
            // Gone entirely is also a pass: the store build is what this guards,
            // and a disk image that stopped checking is a different decision.
            return
        }
        #expect(launch[..<start.lowerBound].suffix(400).contains("#if !APPSTORE"), """
            startChecking() is compiled into the store build again — a daily \
            check is the thing guideline 2.4.5(vii) refused
            """)
    }

    @Test func theUpdatesScreenIsNotOfferedByTheStoreBuild() throws {
        let settings = try Self.app("Settings/SettingsView.swift")
        #expect(settings.contains("#if APPSTORE") && settings.contains("!= .updates"), """
            SettingsView lists the Updates section in the store build again — \
            the screen whose whole subject is a newer version
            """)
        // The whole file, not a branch inside it: the guard stands before the
        // first import, so the store build compiles none of the screen.
        let pane = try Self.app("Settings/UpdatesPane.swift")
        var guardIsFirst = false
        if let opened = pane.range(of: "#if !APPSTORE")?.lowerBound,
           let imported = pane.range(of: "import")?.lowerBound {
            guardIsFirst = opened < imported
        }
        #expect(guardIsFirst && pane.hasSuffix("#endif\n"), """
            UpdatesPane is compiled into the store build again — the store copy \
            has no state it could show
            """)
    }

    @Test func theMenuAndTheFooterSayNothingAboutVersions() throws {
        let menu = try Self.app("StatusItemController.swift")
        guard let item = menu.range(of: "Check for updates…") else { return }
        #expect(menu[..<item.lowerBound].suffix(400).contains("#if !APPSTORE"), """
            the menu offers a check in the store build again
            """)

        // Anchored on the button, not on the words it prints. `footerTitle`
        // holds the first "Check for updates" in the file and carries its own
        // guard, so a check that searched for the words passed with the button
        // itself left in the store build — found by removing the guard and
        // watching this suite stay green.
        let settings = try Self.app("Settings/SettingsView.swift")
        guard let button = settings.range(of: "Button(footerTitle)") else { return }
        #expect(settings[..<button.lowerBound].suffix(400).contains("#if !APPSTORE"), """
            the settings footer offers a check in the store build again
            """)
    }

    /// The store lane's reader is gone, not switched off. A flag would have left
    /// `StoreListing` and the lookup URL in the binary with one `if` in front of
    /// them — and the previous rejection, over
    /// `com.apple.security.network.server`, came from an automated read of the
    /// binary rather than from anybody using the app.
    @Test func nothingInTheAppKnowsHowToAskTheStore() throws {
        let model = try Self.app("UpdateModel.swift")
        #expect(!model.contains("case .appStore"), """
            UpdateModel has an App Store channel again
            """)
        #expect(!model.contains("StoreListing"), """
            UpdateModel reads the App Store's lookup record again
            """)

        var offenders: [String] = []
        for file in try Self.swiftFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains("itunes.apple.com") { offenders.append(file.lastPathComponent) }
        }
        #expect(offenders.isEmpty, """
            \(offenders.joined(separator: ", ")) names itunes.apple.com — the \
            store's lookup record is the release feed guideline 2.4.5(vii) \
            refused, whoever reads it
            """)
    }

    // MARK: - reading

    private static func app(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent("App/\(path)"), encoding: .utf8)
    }

    private static func swiftFiles() throws -> [URL] {
        var found: [URL] = []
        for name in ["App", "Packages/Core/Sources", "Widget"] {
            let root = repositoryRoot.appendingPathComponent(name)
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
            else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" { found.append(url) }
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
