import Foundation
import ProviderKit
import Preferences

public struct ThresholdEvent: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case crossed(Int)   // a threshold was crossed upward
        case recovered      // the limit reset, the account is free again
    }

    public let accountID: String
    public let windowID: String
    public let accountName: String
    public let kind: Kind
}

/// Remembers the previous reading and emits an event only on a crossing.
/// Without that, a five-minute background poll would become a stream of alerts.
///
/// What it remembers has to outlive both a settings change and a relaunch. It did
/// neither: the map lived only in memory, so an app that came back while an
/// account was already past a threshold had nothing below it to cross from, and
/// the warning never arrived for that window at all — not late, never. Changing
/// any notification setting rebuilt the tracker and erased the same thing.
public struct ThresholdTracker: Sendable {
    private let thresholds: [Int]        // descending
    private let notifyOnRecovery: Bool
    private let scope: WindowScope
    private let quietHours: QuietHours?
    private let calendar: Calendar
    private static let recoveryLevel = 50.0

    private var previous: [Key: Double] = [:]
    private var seenAtLeastOnce = false

    fileprivate struct Key: Hashable { let account: String; let window: String }

    /// Everything the tracker knows, so a new one can pick up where the last left
    /// off. Opaque on purpose: the shape is the tracker's business, but it has to
    /// survive being handed across a rebuild.
    public struct Baseline: Sendable, Equatable {
        fileprivate let readings: [Key: Double]
        public var isEmpty: Bool { readings.isEmpty }
    }

    public var baseline: Baseline { Baseline(readings: previous) }

    /// Adopt a baseline from a tracker being replaced.
    public mutating func restore(_ baseline: Baseline) {
        previous = baseline.readings
        seenAtLeastOnce = !previous.isEmpty
    }

    /// Take the baseline from a reading rather than from another tracker — the
    /// snapshot on disk after a relaunch.
    ///
    /// Deliberately not the same as feeding the reading to `events(for:)`: this
    /// records where every window stood and emits nothing, because whatever
    /// happened before the app started is not news it can honestly deliver.
    public mutating func seed(from snapshots: [AccountSnapshot]) {
        for snapshot in snapshots where snapshot.failure == nil {
            for window in snapshot.windows {
                previous[Key(account: snapshot.id, window: window.id)] = window.percent
            }
        }
        seenAtLeastOnce = !previous.isEmpty
    }

    public init(
        thresholds: [Int] = [95, 80],
        notifyOnRecovery: Bool = true,
        scope: WindowScope = .both,
        quietHours: QuietHours? = nil,
        calendar: Calendar = .current
    ) {
        self.thresholds = thresholds.sorted(by: >)
        self.notifyOnRecovery = notifyOnRecovery
        self.scope = scope
        self.quietHours = quietHours
        self.calendar = calendar
    }

    /// `now` has no default on purpose. It decides whether the quiet hours are
    /// in force, and a test that set them and left the moment to the clock passed
    /// all evening and failed at one in the morning — which this log already says
    /// is worse than failing. The one caller in the app passes `Date()` and always
    /// did, so requiring it costs nothing and makes that trap unreachable.
    public mutating func events(
        for snapshots: [AccountSnapshot], now: Date
    ) -> [ThresholdEvent] {
        var events: [ThresholdEvent] = []
        var current: [Key: Double] = [:]

        // Quiet hours mute notifications but the reading is still recorded:
        // otherwise a batch of overnight events would arrive in the morning.
        let silent = quietHours?.contains(now, calendar: calendar) ?? false

        for snapshot in snapshots where snapshot.failure == nil {
            for window in snapshot.windows {
                let key = Key(account: snapshot.id, window: window.id)
                current[key] = window.percent

                guard seenAtLeastOnce, let before = previous[key],
                      scope.includes(windowID: window.id), !silent
                else { continue }
                let level = window.percent

                if let crossed = thresholds.first(where: {
                    before < Double($0) && level >= Double($0)
                }) {
                    events.append(ThresholdEvent(
                        accountID: snapshot.id, windowID: window.id,
                        accountName: snapshot.displayName, kind: .crossed(crossed)
                    ))
                } else if notifyOnRecovery,
                          before >= Self.recoveryLevel, level < Self.recoveryLevel {
                    events.append(ThresholdEvent(
                        accountID: snapshot.id, windowID: window.id,
                        accountName: snapshot.displayName, kind: .recovered
                    ))
                }
            }
        }

        previous = current
        seenAtLeastOnce = true
        return events
    }
}
