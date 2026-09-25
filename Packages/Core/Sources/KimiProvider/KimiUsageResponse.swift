import Foundation
import ProviderKit

/// What a Kimi Code subscription says is left of its windows.
public struct KimiUsageResponse: Sendable, Hashable {
    public let windows: [LimitWindow]

    /// The two windows this app draws, and the identifiers it already has.
    ///
    /// `limit_5h` and `limit_7d` are a five-hour window and a seven-day one,
    /// which are `session` and `weekly` exactly. Nothing is named, no catalogue
    /// gains a key, no column is remeasured.
    private static let known: [(field: String, id: String)] = [
        ("limit_5h", "session"),
        ("limit_7d", "weekly"),
    ]

    /// The reply also carries `usages.limit_month_total` on some plans, and two
    /// older shapes beside `usages`: string counters under `usage`, and a
    /// `limits` array whose entries carry a `window.duration` in minutes.
    ///
    /// None of the three is read. The monthly envelope would be a third bar in
    /// a row built for two — the cost `docs/DECISIONS.md` records for Copilot —
    /// and the older shapes are known to exist without their field names being
    /// known. A fallback written from a description rather than from a reply is
    /// a fallback that can quietly produce a number, and a number this app
    /// cannot stand behind is worse than a row that says it could not read.
    public static func parse(_ data: Data) throws -> KimiUsageResponse {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderFailure(kind: .malformed, diagnostic: "usage reply is not an object")
        }

        guard let usages = root["usages"] as? [String: Any] else {
            throw ProviderFailure(
                kind: .malformed,
                diagnostic: "usage reply has no usages; the older shapes are not read")
        }

        let windows = known.compactMap { entry -> LimitWindow? in
            guard let window = usages[entry.field] as? [String: Any],
                  let percent = used(window) else { return nil }
            return LimitWindow(id: entry.id, percent: percent, resetsAt: reset(window))
        }

        guard !windows.isEmpty else {
            throw ProviderFailure(
                kind: .malformed, diagnostic: "usage reply held no window this app knows")
        }
        return KimiUsageResponse(windows: windows)
    }

    /// `used_ratio` is a fraction of the window that has gone — `0.0866` is
    /// eight and a half per cent used, not ninety-one remaining. The name says
    /// so and is worth checking against anyway, because the other key-based
    /// service here names its allowance `usage` and means the opposite.
    private static func used(_ window: [String: Any]) -> Double? {
        guard let ratio = (window["used_ratio"] as? NSNumber)?.doubleValue,
              ratio.isFinite else { return nil }
        return min(max(ratio * 100, 0), 100)
    }

    /// An ISO 8601 instant, not the epoch milliseconds the other key-based
    /// service sends. Read with a fixed formatter rather than the locale's,
    /// which is what makes it the same instant on every Mac.
    private static func reset(_ window: [String: Any]) -> Date? {
        guard let text = window["reset_time"] as? String, !text.isEmpty else { return nil }
        let strict = ISO8601DateFormatter()
        strict.formatOptions = [.withInternetDateTime]
        if let read = strict.date(from: text) { return read }
        // Some replies carry fractional seconds. Asked for separately because a
        // formatter told to expect them refuses an instant without.
        strict.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return strict.date(from: text)
    }
}
