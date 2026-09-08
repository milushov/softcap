import Foundation

/// Runs a body on an interval, and lets the interval change without disturbing
/// a run already under way.
///
/// The separation is the whole point. The schedule is cancellable — it has to
/// be, because the interval changes when the window opens and closes. The work
/// is not: a poll holds network requests, and cancelling the task they run in
/// cancels them mid-flight, which arrives as `URLError -999` and reads as a
/// network failure.
///
/// That is not hypothetical. The interval was re-armed from
/// `isPopoverOpen.didSet`, so every open and close of the window cancelled a
/// poll in progress. With one account it almost never collided; with three the
/// poll ran long enough that opening the window to look at the accounts was
/// what stopped them from loading.
public final class PollScheduler: @unchecked Sendable {
    private let lock = NSLock()
    private var schedule: Task<Void, Never>?

    public init() {}

    /// Replaces the schedule. Work already running is left alone.
    public func restart(every interval: TimeInterval, run body: @escaping @Sendable () async -> Void) {
        lock.lock()
        schedule?.cancel()
        schedule = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                // An unstructured task is not a child, so cancelling the
                // schedule above cannot reach the body once it has started.
                // Awaiting it here keeps two runs from overlapping.
                await Task { await body() }.value
            }
        }
        lock.unlock()
    }

    public func stop() {
        lock.lock()
        schedule?.cancel()
        schedule = nil
        lock.unlock()
    }

    deinit { schedule?.cancel() }
}
