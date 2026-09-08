import Foundation
import ProviderKit

/// Anthropic returns times with microseconds and an offset:
/// "2026-08-30T14:00:00.277644+00:00". Both that and "…701Z" with milliseconds
/// are known to parse.
///
/// `Date.ISO8601FormatStyle` is used rather than `ISO8601DateFormatter`: the
/// latter is not `Sendable`, so a `static let` of it fails Swift 6 concurrency
/// checking.
public enum ClaudeTimestamp {
    private static let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    public static func date(from text: String) -> Date? { try? style.parse(text) }
}

public enum ClaudeUsageResponse {

    private struct Body: Decodable {
        let fiveHour: Legacy?
        let sevenDay: Legacy?
        let limits: [Limit]?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour", sevenDay = "seven_day", limits
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            fiveHour = try? container.decodeIfPresent(Legacy.self, forKey: .fiveHour)
            sevenDay = try? container.decodeIfPresent(Legacy.self, forKey: .sevenDay)
            limits = (try? container.decode([FailableLimit].self, forKey: .limits))?
                .compactMap(\.value)
        }

        /// A wrapper that swallows the failure of a single array element.
        struct FailableLimit: Decodable {
            let value: Limit?
            init(from decoder: any Decoder) throws {
                value = try? Limit(from: decoder)
            }
        }

        struct Legacy: Decodable {
            let utilization: Double
            let resetsAt: String?
            enum CodingKeys: String, CodingKey { case utilization, resetsAt = "resets_at" }
        }

        /// Entries are decoded one at a time and independently: the service may
        /// add a new window kind or change the shape of `scope`, and one such
        /// entry must not invalidate the whole response. The same principle is
        /// already applied to Codex session lines.
        struct Limit: Decodable {
            let kind: String
            let percent: Double
            let resetsAt: String?
            let hasScope: Bool

            enum CodingKeys: String, CodingKey { case kind, percent, resetsAt = "resets_at", scope }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                kind = try container.decode(String.self, forKey: .kind)
                percent = try container.decode(Double.self, forKey: .percent)
                resetsAt = try? container.decodeIfPresent(String.self, forKey: .resetsAt)
                // The shape of `scope` does not matter — only whether it is set.
                hasScope = container.contains(.scope)
                    && (try? container.decodeNil(forKey: .scope)) == false
            }
        }
    }

    public static func windows(from data: Data) throws -> [LimitWindow] {
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else {
            throw ProviderFailure(kind: .malformed, diagnostic: "usage response not parsed")
        }

        let fromLimits = (body.limits ?? []).compactMap(window(from:))
        if !fromLimits.isEmpty { return sorted(fromLimits) }

        // The limits array is empty, so fall back to the legacy fields.
        var legacy: [LimitWindow] = []
        if let five = body.fiveHour {
            legacy.append(LimitWindow(id: "session", percent: five.utilization,
                resetsAt: five.resetsAt.flatMap { ClaudeTimestamp.date(from: $0) }
            ))
        }
        if let week = body.sevenDay {
            legacy.append(LimitWindow(id: "weekly", percent: week.utilization,
                resetsAt: week.resetsAt.flatMap { ClaudeTimestamp.date(from: $0) }
            ))
        }

        guard !legacy.isEmpty else {
            throw ProviderFailure(kind: .malformed, diagnostic: "no limit windows in response")
        }
        return sorted(legacy)
    }

    /// A per-model slice (`scope != null`) is skipped: it duplicates the overall
    /// weekly limit and only adds noise to a compact list.
    private static func window(from limit: Body.Limit) -> LimitWindow? {
        guard !limit.hasScope else { return nil }
        let reset = limit.resetsAt.flatMap { ClaudeTimestamp.date(from: $0) }

        switch limit.kind {
        case "session":
            return LimitWindow(id: "session", percent: limit.percent, resetsAt: reset)
        case "weekly_all":
            return LimitWindow(id: "weekly", percent: limit.percent, resetsAt: reset)
        default:
            return nil   // an unfamiliar window kind is ignored, the rest survive
        }
    }

    /// Row order in a card: the five-hour window first, then the weekly one.
    /// Given by an explicit table rather than comparing one field: a predicate
    /// like `$0.id == "session"` is not a strict ordering, which leaves the sort
    /// result undefined.
    private static func sorted(_ windows: [LimitWindow]) -> [LimitWindow] {
        let rank = ["session": 0, "weekly": 1]
        return windows.sorted { (rank[$0.id] ?? 99) < (rank[$1.id] ?? 99) }
    }
}
