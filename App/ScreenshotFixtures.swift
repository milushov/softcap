#if SCREENSHOTS
import Foundation
import Credentials
import Preferences
import ProviderKit
import Monitoring

/// The accounts a store screenshot shows.
///
/// Compiled only into a screenshot build, so nothing here is in the app anybody
/// installs. The whole file exists because the alternative was photographing
/// the author's own accounts: a store listing is permanent and public, and the
/// real window names four mailboxes and says how much of each subscription has
/// been spent.
///
/// The addresses are `example.com` — reserved by RFC 2606 for exactly this, and
/// required here by the repository's rule against putting a real mail address in
/// a published artefact.
///
/// The numbers are chosen to show the whole colour scale in one window rather
/// than to be typical: one account calm, one warm, one nearly out, one barely
/// touched. A screenshot has to earn its place in a row of five, and four rows
/// all sitting at forty percent say nothing about what the app is for.
enum ScreenshotFixtures {

    /// Fixed offsets from launch rather than fixed dates: a reset that reads
    /// "resets in 3h" is right whenever the screenshot is taken, and a literal
    /// date would be in the past by the time the listing is reviewed.
    private static func inHours(_ hours: Double) -> Date {
        Date().addingTimeInterval(hours * 3600)
    }

    static var accounts: [AccountSnapshot] {
        [
            AccountSnapshot(
                id: "claude/fixture-1",
                provider: .claude,
                displayName: "ada@example.com",
                planLabel: "Max 20x",
                windows: [
                    LimitWindow(id: "session", percent: 34, resetsAt: inHours(3.5)),
                    LimitWindow(id: "weekly", percent: 58, resetsAt: inHours(82)),
                ],
                freshness: .live(Date()),
                failure: nil
            ),
            AccountSnapshot(
                id: "claude/fixture-2",
                provider: .claude,
                displayName: "grace@example.com",
                planLabel: "Pro",
                windows: [
                    LimitWindow(id: "session", percent: 71, resetsAt: inHours(1.2)),
                    LimitWindow(id: "weekly", percent: 83, resetsAt: inHours(54)),
                ],
                freshness: .live(Date()),
                failure: nil
            ),
            AccountSnapshot(
                id: "codex/fixture-1",
                provider: .codex,
                displayName: "linus@example.com",
                planLabel: "Plus",
                windows: [
                    LimitWindow(id: "session", percent: 92, resetsAt: inHours(0.6)),
                    LimitWindow(id: "weekly", percent: 64, resetsAt: inHours(110)),
                ],
                freshness: .live(Date()),
                failure: nil
            ),
            AccountSnapshot(
                id: "codex/fixture-2",
                provider: .codex,
                displayName: "hedy@example.com",
                planLabel: "Pro",
                windows: [
                    LimitWindow(id: "session", percent: 18, resetsAt: inHours(4.8)),
                    LimitWindow(id: "weekly", percent: 27, resetsAt: inHours(96)),
                ],
                freshness: .live(Date()),
                failure: nil
            ),
        ]
    }

    /// The Accounts screen reads the keychain and scans `~/.codex` rather than
    /// the snapshots, so it needs the same four accounts said a second way.
    ///
    /// The states are the healthy ones on purpose. `needsLogin` is a real and
    /// common state, and it draws a row asking to sign in — true of the app, and
    /// the wrong thing to put in a shop window.
    ///
    /// They are also not interchangeable with the provider beside them. Two of
    /// the four captions name a service themselves — `activeInCLI` reads "token
    /// read from Claude Code" and `localSession` reads "Codex · local session
    /// files" — because only Claude has a CLI whose keychain item this app can
    /// read, and only Codex writes session files. The first draft of this list
    /// gave a Codex account `activeInCLI`, and the screenshot said "Claude"
    /// underneath an address the row had already labelled Codex.
    static var rows: [AccountsPane.AccountRow] {
        [
            AccountsPane.AccountRow(
                id: "claude/fixture-1", handle: "ada@example.com", provider: .claude,
                displayName: "ada@example.com", state: .refreshed),
            AccountsPane.AccountRow(
                id: "claude/fixture-2", handle: "grace@example.com", provider: .claude,
                displayName: "grace@example.com", state: .activeInCLI),
            AccountsPane.AccountRow(
                id: "codex/fixture-1", handle: "linus@example.com", provider: .codex,
                displayName: "linus@example.com", state: .refreshed),
            AccountsPane.AccountRow(
                id: "codex/fixture-2", handle: "hedy@example.com", provider: .codex,
                displayName: "hedy@example.com", state: .localSession),
        ]
    }

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
            value.languageCode = "en"
            value.rowLayout = .twoWindows
            value.showSnapshotAge = true
            // The one screen taken twice. An environment variable rather than a
            // second build: the two windows differ by a setting, and rebuilding
            // to change a setting would make the pair harder to keep identical.
            value.minimalWindow = ProcessInfo.processInfo.environment["SOFTCAP_SHOT_MINIMAL"] == "1"
            // Nothing in a screenshot run should reach the network, and the
            // update check is the one thing that would without being asked.
            value.checksForUpdates = false
            return try? JSONEncoder().encode(value)
        }

        func write(_ data: Data) async {}
    }

    /// A month of weekly readings for the statistics chart.
    ///
    /// Generated rather than written out: the screen draws four weeks, and four
    /// weeks of three-hourly readings is nine hundred numbers. The shape is the
    /// one the real chart has — each account climbs across its week and drops to
    /// nothing when the allowance resets — with the cycles deliberately out of
    /// phase, because four lines resetting on the same evening reads as a
    /// drawing rather than as a measurement.
    static var samples: [UsageSample] {
        let now = Date()
        let step: TimeInterval = 3 * 3600
        let weeks = 4.0
        let peaks: [Double] = [72, 91, 64, 38]
        let phases: [Double] = [0, 2.4, 4.1, 5.6]   // days, so no two resets coincide

        var out: [UsageSample] = []
        for (index, account) in accounts.enumerated() {
            let peak = peaks[index]
            var moment = now.addingTimeInterval(-weeks * 7 * 86400)
            while moment <= now {
                let days = moment.timeIntervalSinceReferenceDate / 86400 + phases[index]
                let throughTheWeek = days.truncatingRemainder(dividingBy: 7) / 7
                // A day's rhythm on top of the week's climb: work happens in
                // bursts, and a perfectly straight ramp is the one shape a real
                // reading never has.
                let daily = 0.05 * sin(moment.timeIntervalSinceReferenceDate / 3600 * 0.26)
                let percent = min(99, max(1, peak * (throughTheWeek + daily)))
                out.append(UsageSample(
                    at: moment, accountID: account.id, windowID: "weekly", percent: percent))
                moment = moment.addingTimeInterval(step)
            }
        }
        return out
    }
}
#endif
