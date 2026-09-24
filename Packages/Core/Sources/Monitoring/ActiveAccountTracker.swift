import Foundation
import ProviderKit

/// Which account is being worked with, judged by whose usage last went up.
///
/// The app may not ask the CLI. It used to — the entry of 2026-08-30, "The
/// active Claude account is read-only", matched the refresh token in the CLI's
/// own keychain item — and that route closed on 2026-09-14, when Softcap
/// stopped opening anybody's keychain item but its own. Nothing else on the
/// machine names the account in use, so the answer is inferred from the polls
/// that happen anyway.
///
/// The constraint pays for itself: reading the CLI would answer for Claude
/// alone, while a rule built on readings answers for every provider, including
/// ones this app has not met yet.
public struct ActiveAccountTracker: Sendable, Equatable {

    /// Below this, a difference between two readings is `Double` noise.
    ///
    /// Not a threshold for "used it enough" — any real rise counts, however
    /// small. A person who spent a tenth of a percent is still the person at
    /// the keyboard.
    public static let floor = 0.01

    /// The last percentage seen for one window of one account.
    private struct Mark: Hashable {
        let account: String
        let window: String
    }

    /// When an account last rose, and by how much.
    private struct Rise: Hashable {
        var at: Date
        var points: Double
    }

    private var marks: [Mark: Double] = [:]
    private var rises: [String: Rise] = [:]

    public init() {}

    /// Picks up where the last run left off.
    ///
    /// A fresh tracker knows nothing, and a menu bar that falls back to the
    /// busiest account for the first minutes of every launch is a feature that
    /// works except when you have just opened your laptop. The history is
    /// loaded at startup anyway, so the tracker is built out of it: each
    /// account's last rise, and each window's last percentage as its mark.
    ///
    /// The kept readings are thinned — no two closer than five minutes, an
    /// unchanged one only every half hour — so a seeded time is approximate. It
    /// only has to order accounts against each other, and for that it is
    /// enough. Marks being up to half an hour stale is harmless in the same
    /// way: the first live poll may then see a rise that happened slightly
    /// earlier, and will credit it to the account that really made it.
    public init(seededFrom history: UsageHistory) {
        // `samples` is kept in ascending time order, so one pass is the same
        // walk `observe` makes poll by poll.
        for sample in history.samples {
            let mark = Mark(account: sample.accountID, window: sample.windowID)
            defer { marks[mark] = sample.percent }
            guard let previous = marks[mark] else { continue }
            let change = sample.percent - previous
            guard change >= Self.floor else { continue }
            rises[sample.accountID] = Rise(at: sample.at, points: change)
        }
    }

    /// The account whose usage rose most recently, or nil if none ever has.
    ///
    /// Ties inside one poll go to the larger rise. That comparison is no more
    /// principled than ranking two providers by rate would be — a Claude point
    /// and a Codex point are different things — but a tie has to break somehow,
    /// it breaks the same way every time, and both accounts genuinely were used
    /// in the last minute, so either answer is defensible.
    public var accountInUse: String? {
        rises.max { left, right in
            left.value.at != right.value.at
                ? left.value.at < right.value.at
                : left.value.points < right.value.points
        }?.key
    }

    /// Takes in one poll.
    ///
    /// Accounts that failed are skipped, for the reason `UsageHistory.record`
    /// skips them: a failed reading is an unknown, not a measurement. Their
    /// marks are left standing, so an account that comes back at the percentage
    /// it left at has not risen.
    public mutating func observe(_ snapshots: [AccountSnapshot], at now: Date) {
        for snapshot in snapshots where snapshot.failure == nil {
            var largest = 0.0
            for window in snapshot.windows {
                let mark = Mark(account: snapshot.id, window: window.id)
                // Runs at the end of this iteration, on every path out of it —
                // including the `continue` below, which is what makes a first
                // sighting set the mark without being counted as a rise.
                defer { marks[mark] = window.percent }

                // First sight of a window is not a rise from zero. Without
                // this, the first poll of all is a rise for every account at
                // once and the answer is whoever happens to be fullest — this
                // feature's name worn by the behaviour it replaces. It also
                // covers an account signing in mid-run at 90%.
                guard let previous = marks[mark] else { continue }

                // A fall is the window resetting. That is the clock, not a
                // person: nothing is recorded, and the mark moves so that the
                // next real rise is measured from where the window now is.
                let change = window.percent - previous
                if change >= Self.floor { largest = max(largest, change) }
            }
            guard largest > 0 else { continue }
            rises[snapshot.id] = Rise(at: now, points: largest)
        }
    }
}
