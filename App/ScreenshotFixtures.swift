#if SCREENSHOTS
import Foundation
import Preferences

/// The settings a store screenshot run uses.
///
/// The accounts, the rows and the history it once held are gone: they are
/// `DemoData` now, the same three the app shows anybody without a subscription
/// and the same three the landing page draws. One set of invented accounts
/// rather than two, so a screenshot in the store, the window on the website and
/// the app on a stranger's machine are one picture. `TheDemoMatchesTheLanding`
/// holds the numbers together.
///
/// What stays here is the part that is about this run rather than about the
/// data: settings held in memory, so a screenshot neither reads the author's
/// own nor writes to them.
enum ScreenshotFixtures {

    /// The settings a screenshot run uses, held in memory.
    ///
    /// The real ones live in `UserDefaults` under the app's identifier, and this
    /// run must do neither thing to them. Not read: the author's language, window
    /// shape and hidden accounts are his, and a store listing should show the app
    /// as it arrives rather than as one machine has arranged it. Not written:
    /// turning the minimal window on for one screenshot would otherwise be a
    /// permanent change to his settings, made by a tool he pointed at a picture.
    struct Storage: PreferencesStorage {
        func read() async -> Data? {
            var value = Preferences.defaults
            value.appearance = .dark
            // The store listing is ten listings, and each one's screenshots
            // have to be in the language its text is written in — a Russian
            // description over an English window is the picture contradicting
            // the page. The language is a setting, so it comes in the same way
            // the window shape does, by environment rather than by rebuilding:
            // one build photographed ten times. English when nothing is named,
            // because that is what a run with no argument used to produce.
            value.languageCode = ProcessInfo.processInfo.environment["SOFTCAP_SHOT_LANG"] ?? "en"
            value.rowLayout = .twoWindows
            value.showSnapshotAge = true
            // The one screen taken twice. An environment variable rather than a
            // second build: the two windows differ by a setting, and rebuilding
            // to change a setting would make the pair harder to keep identical.
            value.minimalWindow = ProcessInfo.processInfo.environment["SOFTCAP_SHOT_MINIMAL"] == "1"
            // Nothing in a screenshot run should reach the network, and the
            // update check is the one thing that would without being asked.
            value.checksForUpdates = false
            // The rows on the Accounts screen are samples, so the switch that
            // governs samples has to be on. Left to resolve itself it reads
            // "off" beside three sample accounts, which is the one thing a
            // store screenshot must not do — state something the picture
            // contradicts.
            value.demoMode = true
            return try? JSONEncoder().encode(value)
        }

        func write(_ data: Data) async {}
    }
}
#endif
