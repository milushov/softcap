import Foundation

/// How often the app looks for a new version, and whether it is time.
public enum UpdateSchedule {

    /// A day. Releases are cut per push to `main` and nobody needs one the hour
    /// it lands; checking more often spends somebody's request budget on a
    /// question whose answer changes rarely.
    public static let interval: TimeInterval = 24 * 60 * 60

    /// Whether a check is due at `now`.
    ///
    /// `now` is required, and deliberately has no default. `ThresholdTracker`
    /// carried one and a test written before midnight failed at one in the
    /// morning with nothing changed — green, committed, pushed, then red. A
    /// caller that must name the moment cannot write that test.
    /// `AskingWhetherToCheckRequiresAMoment` keeps the default from coming back.
    public static func isDue(lastChecked: Date?, now: Date) -> Bool {
        guard let lastChecked else { return true }

        // A clock corrected backwards leaves the last check in the future, and
        // a negative age is never a day: the app would go quiet until the clock
        // caught up with itself.
        guard lastChecked <= now else { return true }

        return now.timeIntervalSince(lastChecked) >= interval
    }

    /// How old an answer already on screen may be before it is worth asking
    /// again. Five minutes, not a day: the screen is somebody looking.
    ///
    /// The floor is the whole reason there is a number here at all. Moving
    /// between the settings panes would otherwise be traffic, and one question
    /// per pane switch is not what anybody meant by opening the screen.
    public static let staleAfter: TimeInterval = 5 * 60

    /// Whether an answer last found at `lastChecked` is old enough to ask again
    /// for somebody now reading it.
    ///
    /// `isDue` answers a different question — whether the app should ask on its
    /// own — and answered it correctly while the Updates screen offered 0.1.3
    /// for the rest of a day in which seven more releases were published. The
    /// screen had no way to ask again, and the daily check was not due for
    /// another seventeen hours.
    public static func isStale(lastChecked: Date?, now: Date) -> Bool {
        guard let lastChecked else { return true }
        // A clock corrected backwards, for the reason written above.
        guard lastChecked <= now else { return true }

        return now.timeIntervalSince(lastChecked) >= staleAfter
    }
}
