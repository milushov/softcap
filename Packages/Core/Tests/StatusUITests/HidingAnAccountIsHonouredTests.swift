import Testing
import Foundation

/// Hiding an account has to reach every place that could show it.
///
/// The setting is written by one control and read by two: the poller, so a
/// hidden account is not fetched at all, and the chart, so its history is not
/// drawn. Both live in the app layer, which has no unit tests — and nothing
/// else was watching them. Delete either read and a hidden account comes back
/// in the window, the widget or the chart, with the switch still off and every
/// test passing.
///
/// A scan, because that is what this layer allows. It cannot prove the filter is
/// right; it can refuse a version where nobody consults the setting at all,
/// which is the failure that would otherwise be silent.
@Suite struct HidingAnAccountIsHonoured {

    private static let readers = [
        ("App/AppModel.swift",
         "the poller would fetch an account the person hid, and it would appear "
         + "in the window and in the widget"),
        ("App/Settings/StatisticsPane.swift",
         "the chart would draw a hidden account's history, ending where it was "
         + "hidden — which everywhere else in that chart means nothing was measured"),
    ]

    @Test func everySurfaceThatCouldShowAnAccountConsultsTheSetting() throws {
        for (path, consequence) in Self.readers {
            let source = try String(
                contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8
            )
            #expect(source.contains("hiddenAccounts"),
                    "\(path) no longer consults hiddenAccounts — \(consequence)")
        }
    }

    /// And something still writes it, or the switch is decoration.
    @Test func theSwitchStillWritesIt() throws {
        let pane = try String(
            contentsOf: Self.root.appendingPathComponent("App/Settings/AccountsPane.swift"),
            encoding: .utf8
        )
        #expect(pane.contains("hiddenAccounts.insert") && pane.contains("hiddenAccounts.remove"),
                "the Accounts pane no longer adds and removes hidden accounts")
    }

    /// Both shortcuts are registered somewhere, and both have a control.
    ///
    /// `openWindowHotKey` and `HotKeyID.openWindow` were carried from the day the
    /// settings screen was built. The plan specified a row for the first and a
    /// registration for it; neither was written. The field was stored and
    /// decoded, the identifier was declared, and the shortcut could not be
    /// recorded and would not have been heard — a setting that existed only in
    /// the file it was saved to. Two entries in the decision log said "both hot
    /// keys" while one of them did nothing.
    @Test func bothShortcutsAreRegisteredAndSettable() throws {
        let app = try Self.sources(under: "App")
        let text = app.map { (try? String(contentsOf: $0, encoding: .utf8)) ?? "" }
            .joined(separator: "\n")

        for (setting, id) in [("openWindowHotKey", "HotKeyID.openWindow"),
                              ("refreshHotKey", "HotKeyID.refresh")] {
            #expect(text.contains("register(") && text.contains(id),
                    "nothing registers \(id), so \(setting) would be heard by nothing")
            #expect(text.contains("path: \\.\(setting)"),
                    "the settings window has no control for \(setting)")
        }
    }

    /// The page mentions the shortcut, and the shortcut exists.
    ///
    /// It was added to the landing the day after it started working. Saying a
    /// menu bar app has a global shortcut is the kind of claim a reader takes on
    /// trust and never checks, which is what makes it worth holding to the code.
    @Test func theLandingOnlyPromisesAShortcutThatExists() throws {
        let page = try String(
            contentsOf: Self.root.appendingPathComponent("site/index.html"), encoding: .utf8
        )
        guard page.range(of: "shortcut", options: .caseInsensitive) != nil else { return }

        let app = try Self.sources(under: "App")
        let text = app.map { (try? String(contentsOf: $0, encoding: .utf8)) ?? "" }
            .joined(separator: "\n")
        #expect(text.contains("HotKeyID.openWindow") && text.contains("register("), """
            the page offers a shortcut that opens the window and nothing registers one
            """)
    }

    private static func sources(under directory: String) throws -> [URL] {
        let root = Self.root.appendingPathComponent(directory)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { return [] }
        var found: [URL] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            found.append(url)
        }
        #expect(found.count > 5, "the App scan found \(found.count) files")
        return found
    }

    private static var root: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
}
