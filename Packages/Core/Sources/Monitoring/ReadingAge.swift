import Foundation

/// How current the figures on screen are, as far as the window should admit.
///
/// The window used to show the time the reading was taken, quietly, in grey —
/// and a spinner whenever a poll was in flight. Neither says anything when a
/// poll stops finishing: the spinner turns for an hour and the clock time
/// reads perfectly plausibly. A reader has to notice for themselves that
/// `2:41 AM` was an hour ago, and nobody does.
public enum ReadingAge: Sendable, Equatable {
    /// Recent enough to leave alone: show the time and say nothing.
    case current
    /// Older than polling should allow. The interval is how old.
    case overdue(TimeInterval)

    public var isOverdue: Bool {
        if case .overdue = self { return true }
        return false
    }
}

/// A reading is overdue once it is older than several polls' worth of time —
/// one missed poll is a hiccup, three in a row is a fault.
///
/// The multiple is applied to the background interval, the slowest cadence the
/// app polls at, so a reading taken while the window was shut is not called
/// stale merely for having been taken then.
public func readingAge(
    lastUpdated: Date?,
    now: Date,
    pollingEvery interval: TimeInterval,
    tolerating multiple: Double = 3
) -> ReadingAge {
    guard let lastUpdated else { return .current }
    let age = now.timeIntervalSince(lastUpdated)
    guard age > interval * multiple else { return .current }
    return .overdue(age)
}
