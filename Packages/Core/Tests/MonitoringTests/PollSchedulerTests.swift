import Testing
import Foundation
@testable import Monitoring

/// Records how a run went, from whatever thread the scheduler used.
private final class Record: @unchecked Sendable {
    private let lock = NSLock()
    private var started = 0
    private var finished = 0
    func begin() { lock.lock(); started += 1; lock.unlock() }
    func end() { lock.lock(); finished += 1; lock.unlock() }
    var counts: (started: Int, finished: Int) {
        lock.lock(); defer { lock.unlock() }; return (started, finished)
    }
}

/// Waits for something to become true rather than sleeping a fixed amount and
/// hoping. A scheduler test is about ordering — did this run finish before that
/// one was allowed to start — and a wall-clock margin tuned on an idle machine
/// is a coin toss on a busy one. One of these failed once during a full build and
/// never again in twelve tries, which is the worst kind of red: it teaches you to
/// re-run rather than to look.
private func waitUntil(
    _ description: String,
    timeout: Duration = .seconds(5),
    _ condition: @Sendable () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}

@Suite struct Scheduling {

    /// The defect this exists for: the interval was re-armed whenever the
    /// window opened or closed, and re-arming cancelled the task the poll was
    /// running in — so its network requests died with `URLError -999` and the
    /// accounts showed "network unavailable".
    @Test func restartingDoesNotCancelARunAlreadyUnderWay() async throws {
        let record = Record()
        let scheduler = PollScheduler()

        scheduler.restart(every: 0.05) {
            record.begin()
            // Long enough that the restart below lands mid-run.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            record.end()
        }

        // Wait for a run to be under way, then re-arm as the window would.
        let ran = await waitUntil("the body started") { record.counts.started >= 1 }
        #expect(ran, "the body never ran")
        scheduler.restart(every: 5) { }

        let finished = await waitUntil("the run finished") {
            let c = record.counts
            return c.started > 0 && c.finished == c.started
        }
        let counts = record.counts
        #expect(finished,
                "a run was cut short: started \(counts.started), finished \(counts.finished)")
        scheduler.stop()
    }

    @Test func stoppingEndsTheSchedule() async throws {
        let record = Record()
        let scheduler = PollScheduler()
        scheduler.restart(every: 0.05) { record.begin(); record.end() }

        _ = await waitUntil("at least one run") { record.counts.finished >= 1 }
        scheduler.stop()
        let afterStop = record.counts.finished

        // Nothing to wait *for* here — the claim is that nothing more happens —
        // so this one stays a plain sleep, comfortably longer than the interval.
        try await Task.sleep(for: .milliseconds(400))
        #expect(record.counts.finished == afterStop, "the schedule kept running after stop()")
    }

    @Test func theBodyRunsRepeatedly() async throws {
        let record = Record()
        let scheduler = PollScheduler()
        scheduler.restart(every: 0.05) { record.begin(); record.end() }

        let twice = await waitUntil("two runs") { record.counts.finished >= 2 }
        #expect(twice, "ran \(record.counts.finished) times")
        scheduler.stop()
    }
}
