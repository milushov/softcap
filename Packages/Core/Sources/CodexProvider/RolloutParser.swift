import Foundation
import ProviderKit

/// Codex writes times with fractional seconds: "2026-08-27T16:47:37.701Z".
///
/// `Date.ISO8601FormatStyle` is used rather than `ISO8601DateFormatter`: the
/// latter is not `Sendable`, so a `static let` of it fails Swift 6 concurrency
/// checking.
public enum CodexTimestamp {
    private static let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    public static func date(from text: String) -> Date? { try? style.parse(text) }
}

public struct RateLimitsEvent: Sendable, Hashable {
    public let capturedAt: Date
    public let planType: String?
    public let windows: [LimitWindow]
}

/// Parses the lines of a Codex session file and extracts the last rate-limit
/// event. The file is JSONL and every line stands alone, so a broken line is
/// simply skipped: losing the whole file over one line is not acceptable.
public enum RolloutParser {

    /// Every rate-limit event in the file, oldest first.
    ///
    /// Codex writes these as it works, so a session file is a record of how the
    /// limit moved — history this app never watched and would otherwise have to
    /// wait a month to gather.
    public static func allEvents(inLines lines: [String]) -> [RateLimitsEvent] {
        lines.compactMap { event(fromLine: $0) }
    }

    /// One line, or `nil` when it carries no rate-limit reading. The file is
    /// JSONL and every line stands alone, so a broken one is skipped rather
    /// than losing the file.
    private static func event(fromLine raw: String) -> RateLimitsEvent? {
        guard raw.contains("\"rate_limits\""),
              let data = raw.data(using: .utf8),
              let line = try? JSONDecoder().decode(Line.self, from: data),
              let limits = line.payload?.rateLimits
        else { return nil }

        let windows = [limits.primary, limits.secondary].compactMap { $0 }.map(window)
        guard !windows.isEmpty else { return nil }

        let captured = line.timestamp
            .flatMap { CodexTimestamp.date(from: $0) }
            ?? Date(timeIntervalSince1970: 0)

        return RateLimitsEvent(
            capturedAt: captured, planType: limits.planType, windows: windows
        )
    }

    private struct Line: Decodable {
        let timestamp: String?
        let payload: Payload?

        struct Payload: Decodable {
            let rateLimits: RateLimits?
            enum CodingKeys: String, CodingKey { case rateLimits = "rate_limits" }
        }

        struct RateLimits: Decodable {
            let planType: String?
            let primary: Window?
            let secondary: Window?
            enum CodingKeys: String, CodingKey {
                case planType = "plan_type", primary, secondary
            }
        }

        struct Window: Decodable {
            let usedPercent: Double
            let windowMinutes: Int
            let resetsAt: Double?
            enum CodingKeys: String, CodingKey {
                case usedPercent = "used_percent"
                case windowMinutes = "window_minutes"
                case resetsAt = "resets_at"
            }
        }
    }

    public static func latestEvent(inLines lines: [String]) throws -> RateLimitsEvent {
        for raw in lines.reversed() {
            if let event = event(fromLine: raw) { return event }
        }

        throw ProviderFailure(
            kind: .noData, diagnostic: "no rate_limits events in codex sessions"
        )
    }

    /// Which window a reading belongs to, taken from its length rather than
    /// from the slot it arrived in.
    ///
    /// `primary` is not always the five-hour window. Codex also sends events
    /// whose `primary` is the weekly one — `window_minutes: 10080` — with
    /// `secondary` null. Reading the slot rather than the length labelled those
    /// weekly figures "5h", which is a wrong number under a right-looking name.
    ///
    /// The threshold is a day: everything Codex has ever sent is either 300
    /// minutes or 10080, and anything new that is shorter than a day belongs
    /// with the short window rather than in a category the interface has no
    /// name for.
    private static func window(_ w: Line.Window) -> LimitWindow {
        LimitWindow(
            id: w.windowMinutes < 24 * 60 ? "session" : "weekly",
            percent: w.usedPercent,
            resetsAt: w.resetsAt.map { Date(timeIntervalSince1970: $0) }
        )
    }
}
