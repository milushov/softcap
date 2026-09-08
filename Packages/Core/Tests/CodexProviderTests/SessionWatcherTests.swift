import Testing
import Foundation
@testable import CodexProvider

/// Waits for the watcher to report rather than sleeping a fixed three seconds.
/// The old form was both slower than it needed to be — three seconds even when
/// the event arrived in a fraction of one — and a coin toss on a loaded machine,
/// which is the same weakness the scheduler's tests had.
private func waitUntil(
    timeout: Duration = .seconds(6),
    _ condition: @Sendable () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return false
}

@Suite struct SessionWatching {

    @Test func missingDirectoryIsReportedNotCrashed() {
        // Codex has never been run — an ordinary state, not a failure.
        let watcher = SessionWatcher(
            directory: URL(fileURLWithPath: "/nonexistent/codex/sessions"),
            onChange: {}
        )
        #expect(watcher.start() == false)
    }

    @Test func startsOnAnExistingDirectory() throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let watcher = SessionWatcher(directory: directory, onChange: {})
        #expect(watcher.start())
        watcher.stop()
    }

    @Test func reportsWritesToTheDirectory() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let signal = Signal()
        let watcher = SessionWatcher(directory: directory) { signal.fire() }
        #expect(watcher.start())
        defer { watcher.stop() }

        try Data("{}".utf8).write(to: directory.appendingPathComponent("rollout.jsonl"))

        // The notification is delayed on purpose: Codex writes in bursts and
        // the watcher waits for one to settle.
        let fired = await waitUntil { signal.fired }
        #expect(fired)
    }

    /// Codex files live in dated subdirectories: `sessions/2026/08/30/…`.
    /// The earlier `DispatchSource` implementation missed writes down there —
    /// this test is what stops a return to non-recursive watching.
    @Test func reportsWritesInNestedDirectories() async throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let signal = Signal()
        let watcher = SessionWatcher(directory: root) { signal.fire() }
        #expect(watcher.start())
        defer { watcher.stop() }

        let nested = root.appendingPathComponent("2026/08/30")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: nested.appendingPathComponent("rollout.jsonl"))

        let fired = await waitUntil { signal.fired }
        #expect(fired)
    }

    @Test func stoppingPreventsFurtherReports() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let signal = Signal()
        let watcher = SessionWatcher(directory: directory) { signal.fire() }
        #expect(watcher.start())
        watcher.stop()

        try Data("{}".utf8).write(to: directory.appendingPathComponent("after-stop.jsonl"))
        try await Task.sleep(for: .seconds(2))
        #expect(signal.fired == false)
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// A flag set from another thread.
private final class Signal: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var fired: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func fire() { lock.lock(); value = true; lock.unlock() }
}
