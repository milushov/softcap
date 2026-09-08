import Foundation
import ProviderKit

/// Keeps the history on disk between runs.
///
/// A separate file from the snapshot: the snapshot is rewritten whole on every
/// poll and is read by the widget, while the history only grows and is read by
/// one screen. Mixing them would mean rewriting a month of readings every
/// minute.
public actor UsageHistoryStore {
    private let url: URL?
    private var history = UsageHistory()
    private var loaded = false

    public init(url: URL?) { self.url = url }

    public func current() -> UsageHistory { history }

    public func load() {
        guard !loaded else { return }
        loaded = true
        guard let url, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(UsageHistory.self, from: data)
        else { return }
        history = decoded
    }

    /// Records a poll and writes the file. Pruning happens here rather than on
    /// read: the file is what grows, and trimming it on the way in keeps a
    /// month's ceiling on its size.
    public func record(_ snapshots: [AccountSnapshot], at now: Date) {
        load()
        let before = history
        history.record(snapshots, at: now)
        history.prune(before: now.addingTimeInterval(-UsageHistory.retention))
        guard history != before else { return }
        write()
    }

    /// Returns how many readings were new, for a caller that wants to say so.
    @discardableResult
    public func merge(_ samples: [UsageSample], now: Date) -> Int {
        load()
        let before = history
        let added = history.merge(samples)
        history.prune(before: now.addingTimeInterval(-UsageHistory.retention))
        guard history != before else { return added }
        write()
        return added
    }

    private func write() {
        guard let url else { return }
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
