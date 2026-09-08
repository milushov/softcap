import Foundation

/// Lets one poll run at a time, and stops a poll that never finishes from
/// stopping every poll after it.
///
/// The guard it replaces was a plain flag: set on entry, cleared on the way out.
/// That is correct as long as the way out is reached. A blocking keychain read
/// or a network call with no deadline never reaches it, and from then on every
/// tick sees the flag, turns around, and the app shows the same reading for as
/// long as it is left running — with nothing on screen to say so. Watched
/// happen twice: the second time the data had been still for twenty-five
/// minutes against a five-minute interval.
///
/// So a run is allowed to start when nothing is running **or** when what is
/// running has been running implausibly long. The stuck one is not killed —
/// cancellation does not reach a blocking call, and pretending otherwise would
/// be a second bug — it is simply no longer allowed to hold the door.
public struct RefreshGate: Sendable, Equatable {
    /// Longer than any honest poll: the HTTP client gives up at 30 seconds and a
    /// poll makes a handful of requests, mostly in parallel with each other.
    public static let stallAfter: TimeInterval = 90

    /// A permit to run, handed back when the run ends.
    ///
    /// Ending takes the permit rather than being a bare call, because a
    /// displaced run is not killed and may still return — long after something
    /// else took its place. A bare `end()` from that latecomer would open the
    /// gate on a poll that is still going, and two polls would run at once.
    public struct Run: Sendable, Equatable {
        fileprivate let startedAt: Date
    }

    private let stallAfter: TimeInterval
    private var current: Run?

    public init(stallAfter: TimeInterval = RefreshGate.stallAfter) {
        self.stallAfter = stallAfter
    }

    public var isRunning: Bool { current != nil }

    /// A permit, or `nil` when a run is under way and has not outlived its
    /// deadline.
    public mutating func begin(at now: Date) -> Run? {
        if let current, now.timeIntervalSince(current.startedAt) < stallAfter { return nil }
        let run = Run(startedAt: now)
        current = run
        return run
    }

    /// Whether the run in progress has outlived its deadline and would be pushed
    /// aside. The caller logs it: a poll that hangs is worth knowing about even
    /// once the app has recovered by itself.
    public func wouldDisplace(at now: Date) -> Bool {
        guard let current else { return false }
        return now.timeIntervalSince(current.startedAt) >= stallAfter
    }

    /// Releases the gate, but only for the run that holds it.
    public mutating func end(_ run: Run) {
        guard current == run else { return }
        current = nil
    }
}
