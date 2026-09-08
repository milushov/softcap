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
}
