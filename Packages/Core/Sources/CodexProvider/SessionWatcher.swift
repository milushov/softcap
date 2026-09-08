import Foundation
import ProviderKit

// FSEvents exists only on macOS. On iOS there are no Codex session files to
// watch either: the phone receives a snapshot from the Mac rather than reading
// local files, so the whole watcher has no meaning there.
#if os(macOS)
import CoreServices

/// Watches the Codex sessions directory and reports when something changes.
///
/// Exists so readings update the moment they are written rather than on a timer.
/// A live request to the service will not do: rate-limit headers arrive only on
/// a successful request, which would make the monitor spend the very quota it
/// watches. Watching is free and yields fresh data exactly while Codex is in use.
///
/// FSEvents is used rather than a `DispatchSource` on a directory descriptor:
/// Codex files live in date subdirectories (`sessions/2026/08/30/…`), and a
/// `DispatchSource` watches only the directory itself, missing nested writes —
/// verified, the notification never arrived.
public final class SessionWatcher: @unchecked Sendable {
    private let directory: URL
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "app.softcap.Softcap.codex-watch")

    /// A lock, not a queue: `stopWatching()` is also called from `deinit`, which
    /// may run on that same queue — `queue.sync` would deadlock (verified, the
    /// test crashed with signal 5).
    private let lock = NSLock()
    private var stream: FSEventStreamRef?
    private var debounce: DispatchWorkItem?

    public init(
        directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions"),
        onChange: @escaping @Sendable () -> Void
    ) {
        self.directory = directory
        self.onChange = onChange
    }

    deinit { stopWatching() }

    /// `false` when the directory is missing — Codex has never been run.
    @discardableResult
    public func start() -> Bool {
        guard FileManager.default.fileExists(atPath: directory.path) else { return false }
        stopWatching()
        lock.lock()
        defer { lock.unlock() }

        // A retained reference with a matching release: when the sessions
        // directory changes the old watcher is destroyed while a callback may
        // already be in flight — an unretained one would touch freed memory.
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(self).toOpaque(),
            retain: nil,
            release: { info in
                guard let info else { return }
                Unmanaged<SessionWatcher>.fromOpaque(info).release()
            },
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<SessionWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.scheduleNotification()
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            [directory.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,   // the system's own event coalescing
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
            )
        ) else { return false }

        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return false
        }
        self.stream = stream
        return true
    }

    public func stop() { stopWatching() }

    /// Codex appends events in bursts, so one user action fires several times.
    /// We wait for the writing to settle, otherwise the app would re-read the
    /// files ten times over.
    private func scheduleNotification() {
        lock.lock()
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        debounce = work
        lock.unlock()
        queue.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    /// A stop may arrive from any thread: from the main one when the directory
    /// changes in settings, from the watch queue when the object is released.
    private func stopWatching() {
        lock.lock()
        defer { lock.unlock() }

        debounce?.cancel()
        debounce = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
#endif
