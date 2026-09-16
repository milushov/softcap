import Foundation
import Credentials
import Monitoring
import Preferences
import ProviderKit

/// The accounts the app shows when nobody has signed in.
///
/// Softcap reads subscription usage, so without a paid Claude or Codex plan and
/// a grant obtained in a browser it has nothing to display — and says "No
/// accounts found", which is true and useless. App Review met exactly that on a
/// clean machine and refused the build twice under guideline 2.1(a). A demo
/// account cannot be given: that would mean live provider credentials handed to
/// a stranger, against those providers' terms and against this repository's rule
/// about published values. So the app carries samples instead.
///
/// The three accounts are the ones the landing page already draws, so the
/// website, the store screenshots and the running app are one picture rather
/// than three. `TheDemoMatchesTheLanding` holds them to
/// `site/src/index.body.html` in both directions.
///
/// The addresses are `example.com`, reserved by RFC 2606 for this, and required
/// here by the rule against putting a real mail address in a published artefact:
/// the real window names the author's own mailboxes and says how much of each
/// subscription he has spent.
enum DemoData {

    /// How much faster the demo clock runs than the real one.
    ///
    /// A five-hour window therefore passes in five minutes, which is what makes
    /// the mode worth having: a session bar gains about a third of a percent per
    /// second, so the number on screen changes every two or three seconds and a
    /// person watching for a moment sees a limit being spent rather than a still
    /// photograph. `sam.k`'s forty-one minutes empty in forty-one seconds and
    /// visibly reset, so a minute of attention shows a whole cycle.
    ///
    /// Weekly windows crawl at this speed, as weekly windows should.
    static let speed: Double = 60

    private static let session: TimeInterval = 5 * 3600
    private static let week: TimeInterval = 7 * 86400

    /// One limit window's whole life: where it starts, when it first resets,
    /// what it climbs to, and what is left of it afterwards.
    ///
    /// A pure description, evaluated against elapsed time and holding no state.
    /// The alternative — a simulation ticking a stored percentage upwards — has
    /// to be started, stopped, restored after a sleep and reasoned about when
    /// two windows disagree. This cannot drift because there is nothing to
    /// drift from.
    private struct Track {
        let windowID: String
        /// Percent at launch. The landing's figure, so the first frame of the
        /// demo is the picture on the website.
        let start: Double
        /// Demo seconds from launch to the first reset. `nil` means the window
        /// never resets and therefore never moves.
        let resetsAfter: TimeInterval?
        /// The window's natural length, used by every cycle after the first.
        let length: TimeInterval
        /// What it reaches at the reset.
        let peak: Double
        /// What it falls back to, rather than zero: a window that resets while
        /// somebody is working does not find them idle.
        let residue: Double

        func percent(at elapsed: TimeInterval) -> Double {
            guard let resetsAfter else { return start }
            if elapsed < resetsAfter {
                return start + (peak - start) * (elapsed / resetsAfter)
            }
            let into = (elapsed - resetsAfter).truncatingRemainder(dividingBy: length)
            return residue + (peak - residue) * (into / length)
        }

        func remaining(at elapsed: TimeInterval) -> TimeInterval? {
            guard let resetsAfter else { return nil }
            if elapsed < resetsAfter { return resetsAfter - elapsed }
            let into = (elapsed - resetsAfter).truncatingRemainder(dividingBy: length)
            return length - into
        }
    }

    private struct Account {
        let id: String
        let provider: ProviderID
        let displayName: String
        let planLabel: String
        let tracks: [Track]
        /// Whether the row carries the "Data from …" badge. One of the three
        /// does, because a stale reading is a state the app has and a row that
        /// demonstrates it is worth more than a third moving bar.
        let stale: Bool
    }

    /// The peaks and residues are chosen so that no two windows crest together.
    /// Four bars arriving at once reads as an animation rather than as a
    /// measurement — the same argument the screenshot history already makes
    /// about resets falling on the same evening.
    private static let accounts: [Account] = [
        Account(
            id: "codex/demo-1", provider: .codex,
            displayName: "alex@example.com", planLabel: "Plus",
            tracks: [
                // No reset, so this one does not move. It is a real Codex state
                // — no session started yet — drawn with a dash where a time
                // would be, and it is the only still bar on screen.
                Track(windowID: "session", start: 0, resetsAfter: nil,
                      length: session, peak: 0, residue: 0),
                Track(windowID: "weekly", start: 39, resetsAfter: 3 * 86400 + 22 * 3600,
                      length: week, peak: 62, residue: 6),
            ],
            stale: true
        ),
        Account(
            id: "claude/demo-1", provider: .claude,
            displayName: "sam@example.com", planLabel: "Max 20x",
            tracks: [
                Track(windowID: "session", start: 16, resetsAfter: 2 * 3600 + 4 * 60,
                      length: session, peak: 88, residue: 2),
                Track(windowID: "weekly", start: 80, resetsAfter: 3 * 86400 + 11 * 3600,
                      length: week, peak: 97, residue: 8),
            ],
            stale: false
        ),
        Account(
            id: "claude/demo-2", provider: .claude,
            displayName: "sam.k@example.com", planLabel: "Max 20x",
            tracks: [
                Track(windowID: "session", start: 100, resetsAfter: 41 * 60,
                      length: session, peak: 100, residue: 3),
                Track(windowID: "weekly", start: 55, resetsAfter: 5 * 86400 + 16 * 3600,
                      length: week, peak: 79, residue: 5),
            ],
            stale: false
        ),
    ]

    /// How old the one stale row claims to be. A fixed distance back rather than
    /// a date, so it always reads as an old reading instead of drifting into the
    /// future the way a literal would.
    private static let staleness: TimeInterval = 18 * 86400

    /// The accounts as they stand a given distance into the demo.
    ///
    /// `resetsAt` is stamped as `now` plus the *demo* remainder, not the real
    /// one. Every view computes the countdown as `resetsAt - now` against the
    /// real clock and none of them is changed for this mode; re-stamping once a
    /// second is what makes the label read 41m at launch and lose a minute every
    /// second afterwards. The accelerated clock is meant to be visible — it is
    /// the whole point of the mode — so it is shown rather than hidden.
    static func snapshots(since launch: Date, now: Date = Date()) -> [AccountSnapshot] {
        let elapsed = max(0, now.timeIntervalSince(launch)) * speed
        return accounts.map { account in
            AccountSnapshot(
                id: account.id,
                provider: account.provider,
                displayName: account.displayName,
                planLabel: account.planLabel,
                windows: account.tracks.map { track in
                    LimitWindow(
                        id: track.windowID,
                        percent: track.percent(at: elapsed).rounded(),
                        resetsAt: track.remaining(at: elapsed).map { now.addingTimeInterval($0) }
                    )
                },
                freshness: account.stale
                    ? .snapshot(now.addingTimeInterval(-staleness))
                    : .live(now),
                failure: nil
            )
        }
    }

    /// The same three accounts said the way the Accounts screen wants them.
    ///
    /// That screen reads the keychain rather than the snapshots, and in this
    /// mode it must not: there may be no keychain item to read, and asking would
    /// raise a system prompt in front of somebody who has not signed in to
    /// anything. Every row is `refreshed` — `needsLogin` draws a row asking to
    /// sign in, which is true of the app and the wrong thing to put in front of
    /// somebody being shown what the app does.
    static var rows: [AccountsPane.AccountRow] {
        accounts.map { account in
            AccountsPane.AccountRow(
                id: account.id, handle: account.displayName, provider: account.provider,
                displayName: account.displayName, state: .refreshed
            )
        }
    }

    /// A month of weekly readings for the statistics chart.
    ///
    /// Generated rather than written out: the screen draws four weeks, and four
    /// weeks of three-hourly readings is seven hundred numbers. The shape is the
    /// one the real chart has — each account climbs across its week and drops to
    /// nothing when the allowance resets — with the cycles deliberately out of
    /// phase, because lines resetting on the same evening read as a drawing
    /// rather than as a measurement.
    ///
    /// Held in memory by the caller. Merging these into the real history file
    /// would overwrite a month of somebody's own readings with invented ones.
    static func samples(now: Date = Date()) -> [UsageSample] {
        let step: TimeInterval = 3 * 3600
        let weeks = 4.0
        let phases: [Double] = [0, 2.4, 4.1]   // days, so no two resets coincide

        var out: [UsageSample] = []
        for (index, account) in accounts.enumerated() {
            guard let weekly = account.tracks.first(where: { $0.windowID == "weekly" })
            else { continue }
            let peak = weekly.peak
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
