import Foundation
import ProviderKit

/// A run of readings with no break in them, for one account.
///
/// Splitting matters: the app is not always running, and a line drawn straight
/// across the hours it was asleep would claim a steady figure nobody measured.
public struct UsageSegment: Sendable, Hashable {
    public let accountID: String
    public let points: [UsageSample]
}

/// Readings kept over time, so usage can be seen rather than guessed at.
///
/// Recording is deliberately stingy. A poll runs as often as once a minute, and
/// a percentage that has not moved says nothing new — but a value that never
/// changes is also not the same as a gap, so a reading is kept from time to time
/// even when it repeats. That heartbeat is what makes a gap recognisable.
public struct UsageHistory: Codable, Sendable, Equatable {
    /// Kept in ascending time order.
    public private(set) var samples: [UsageSample]

    /// A reading is kept when it differs by at least this much.
    public static let significantChange = 1.0
    /// No two kept readings of the same window are closer together than this.
    public static let minimumSpacing: TimeInterval = 5 * 60
    /// An unchanged reading is kept anyway once this long has passed.
    public static let heartbeat: TimeInterval = 30 * 60
    /// A quiet spell longer than this is a gap, not a flat line.
    public static let gapAfter: TimeInterval = 2 * 60 * 60
    /// How far back readings are kept.
    public static let retention: TimeInterval = 35 * 24 * 60 * 60

    public init(samples: [UsageSample] = []) {
        self.samples = samples.sorted { $0.at < $1.at }
    }

    /// Readings are decoded one at a time, and one that will not decode is
    /// dropped rather than taking the file with it.
    ///
    /// The synthesised decoder refuses the whole array if a single element is
    /// malformed — a truncated write, a field added to `UsageSample` by a later
    /// build — and `UsageHistoryStore.load` answers a refusal by starting empty.
    /// A month of readings is not something to lose to one bad entry, and the
    /// chart is honest about gaps, so losing a few is a shape it already draws.
    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        var readings = try box.nestedUnkeyedContainer(forKey: .samples)
        var kept: [UsageSample] = []
        while !readings.isAtEnd {
            if let sample = try? readings.decode(UsageSample.self) {
                kept.append(sample)
            } else {
                // The element has to be consumed either way, or the loop never
                // advances past the one that failed.
                _ = try? readings.decode(Discarded.self)
            }
        }
        samples = kept.sorted { $0.at < $1.at }
    }

    /// Consumes one element of unknown shape.
    private struct Discarded: Decodable {
        init(from decoder: any Decoder) throws { _ = try decoder.singleValueContainer() }
    }

    /// Records a poll's readings, keeping only what adds something.
    ///
    /// Accounts that failed are skipped: a failure means the reading is unknown,
    /// and writing the previous value again would invent a measurement.
    public mutating func record(_ snapshots: [AccountSnapshot], at now: Date) {
        for snapshot in snapshots where snapshot.failure == nil {
            for window in snapshot.windows {
                let last = lastSample(account: snapshot.id, window: window.id)
                guard shouldKeep(window.percent, after: last, at: now) else { continue }
                samples.append(UsageSample(
                    at: now, accountID: snapshot.id,
                    windowID: window.id, percent: window.percent
                ))
            }
        }
        samples.sort { $0.at < $1.at }
    }

    /// Thins a run of readings by the rule the app records under.
    ///
    /// Imported readings arrive at whatever rate their source wrote them —
    /// Codex logs one on every turn, which came to 822 in a single day. Keeping
    /// them all would mean one history holding two kinds of density, and a
    /// claim about how much is kept that is only true of half the file.
    ///
    /// Deterministic and independent of what is already stored, so importing
    /// the same files twice yields the same readings and `merge` drops them.
    public static func thinned(_ incoming: [UsageSample]) -> [UsageSample] {
        var lastKept: [Pair: UsageSample] = [:]
        var kept: [UsageSample] = []
        for sample in incoming.sorted(by: { $0.at < $1.at }) {
            let key = Pair(account: sample.accountID, window: sample.windowID)
            guard shouldKeep(sample.percent, after: lastKept[key], at: sample.at) else { continue }
            lastKept[key] = sample
            kept.append(sample)
        }
        return kept
    }

    /// Adds readings from elsewhere — Codex writes its own history into session
    /// files, so a month of it exists before this app ever ran.
    ///
    /// Duplicates are dropped by timestamp, so importing twice is harmless.
    /// Returns how many were new. The count matters because the caller had been
    /// reporting how many it *offered*: the Codex import announced "imported 73
    /// codex readings" on every launch, having added none of them for weeks. A
    /// number nobody could check, in a line written to be checked.
    @discardableResult
    public mutating func merge(_ incoming: [UsageSample]) -> Int {
        var seen = Set(samples.map { Key($0) })
        var added = 0
        for sample in incoming where !seen.contains(Key(sample)) {
            seen.insert(Key(sample))
            samples.append(sample)
            added += 1
        }
        samples.sort { $0.at < $1.at }
        return added
    }

    public mutating func prune(before cutoff: Date) {
        samples.removeAll { $0.at < cutoff }
    }

    /// One window's readings, per account, split where recording stopped.
    ///
    /// `only` is the set of accounts to draw, or nil for all of them. Hiding an
    /// account stops it being polled, so its line would simply stop — and a line
    /// that stops means, everywhere else in this chart, that nothing was
    /// measured. Someone who hid an account would be shown their own choice as
    /// an outage.
    public func segments(
        windowID: String, since: Date, only: Set<String>? = nil,
        gapAfter gap: TimeInterval = UsageHistory.gapAfter
    ) -> [UsageSegment] {
        let wanted = samples.filter {
            $0.windowID == windowID && $0.at >= since && (only?.contains($0.accountID) ?? true)
        }
        var byAccount: [String: [UsageSample]] = [:]
        for sample in wanted { byAccount[sample.accountID, default: []].append(sample) }

        return byAccount.keys.sorted().flatMap { account -> [UsageSegment] in
            split(byAccount[account] ?? [], gap: gap)
                .filter { !$0.isEmpty }
                .map { UsageSegment(accountID: account, points: $0) }
        }
    }

    /// The accounts present in a window's readings, in a stable order — the
    /// chart assigns colours from this, and a colour that moved between redraws
    /// would be worse than no colour at all.
    public func accountIDs(windowID: String, since: Date, only: Set<String>? = nil) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for sample in samples where sample.windowID == windowID && sample.at >= since
            && (only?.contains(sample.accountID) ?? true) {
            if seen.insert(sample.accountID).inserted { ordered.append(sample.accountID) }
        }
        return ordered.sorted()
    }

    // MARK: - internals

    private struct Key: Hashable {
        let at: Date, account: String, window: String
        init(_ s: UsageSample) { at = s.at; account = s.accountID; window = s.windowID }
    }

    private struct Pair: Hashable { let account: String, window: String }

    private func lastSample(account: String, window: String) -> UsageSample? {
        samples.last { $0.accountID == account && $0.windowID == window }
    }

    private func shouldKeep(_ percent: Double, after last: UsageSample?, at now: Date) -> Bool {
        Self.shouldKeep(percent, after: last, at: now)
    }

    private static func shouldKeep(_ percent: Double, after last: UsageSample?, at now: Date) -> Bool {
        guard let last else { return true }
        let elapsed = now.timeIntervalSince(last.at)
        guard elapsed >= Self.minimumSpacing else { return false }
        if abs(percent - last.percent) >= Self.significantChange { return true }
        return elapsed >= Self.heartbeat
    }

    private func split(_ points: [UsageSample], gap: TimeInterval) -> [[UsageSample]] {
        var runs: [[UsageSample]] = []
        var current: [UsageSample] = []
        for point in points {
            if let previous = current.last, point.at.timeIntervalSince(previous.at) > gap {
                runs.append(current)
                current = []
            }
            current.append(point)
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }
}
