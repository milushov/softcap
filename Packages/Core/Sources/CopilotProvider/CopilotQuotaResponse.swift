import Foundation
import ProviderKit

/// What the service says about a person's plan and what is left of it.
public struct CopilotQuotaResponse: Sendable, Hashable {
    public let planLabel: String
    public let windows: [LimitWindow]

    /// The one allowance this app reports, and the identifier it reports it
    /// under. `premium_interactions` is a wire name; a row is not the place to
    /// read one.
    ///
    /// The reply carries three — `chat` and `completions` as well — and only
    /// this one is drawn. On every paid plan the other two come back unlimited
    /// and would be two bars reading nought beside something that cannot run
    /// out; on the free plan they are real, and are the price of this choice.
    ///
    /// What buys that price is the row itself. The period column is one width
    /// shared by every row on screen, so that a glance can read down it, and it
    /// is sized from the labels it may have to hold; the full row fixes it at
    /// 34 points; the compact layout is two bars; the "Primary window" setting
    /// offers the five-hour or the weekly. All of it was built for one window
    /// or two, and a third — labelled with a word longer than any of them —
    /// widens every Claude and Codex row on screen for a service those rows are
    /// not from.
    ///
    /// So one window, named for its period the way the other two services name
    /// theirs. `docs/DECISIONS.md` carries this with what it cost.
    private static let kinds: [(wire: String, id: String)] = [
        ("premium_interactions", "premium"),
    ]

    public static func parse(_ data: Data) throws -> CopilotQuotaResponse {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderFailure(kind: .malformed, diagnostic: "usage reply is not an object")
        }

        // Absent or unreadable is malformed, as it is for every other service
        // here: a reply we cannot understand must never become a row reading
        // zero, which is a statement about the person's account rather than
        // about our failure to read it.
        guard let snapshots = root["quota_snapshots"] as? [String: Any] else {
            throw ProviderFailure(kind: .malformed, diagnostic: "usage reply has no quota snapshots")
        }

        let fallbackReset = reset(root["quota_reset_date"])

        let windows = kinds.compactMap { kind -> LimitWindow? in
            guard let entry = snapshots[kind.wire] as? [String: Any] else { return nil }
            guard let percent = used(entry) else { return nil }
            return LimitWindow(
                id: kind.id,
                percent: percent,
                resetsAt: reset(entry["quota_reset_date"]) ?? fallbackReset)
        }

        return CopilotQuotaResponse(plan: root, windows: windows)
    }

    private init(plan root: [String: Any], windows: [LimitWindow]) {
        // The service's own word for the plan, tidied but not invented. A dash
        // when it does not say, which is what every other row without a plan
        // already shows.
        let raw = (root["copilot_plan"] as? String) ?? (root["access_type_sku"] as? String)
        self.planLabel = raw.map {
            $0.split(separator: "_").map(\.capitalized).joined(separator: " ")
        }.flatMap { $0.isEmpty ? nil : $0 } ?? "—"
        self.windows = windows
    }

    /// How full an allowance is, or `nil` when it is not an allowance at all.
    ///
    /// An unlimited allowance is dropped rather than drawn at zero. A bar
    /// reading 0% beside something that cannot run out is a false statement
    /// about the one thing this app exists to report, and on a paid plan it
    /// would be two of the three rows.
    private static func used(_ entry: [String: Any]) -> Double? {
        if (entry["unlimited"] as? Bool) == true { return nil }
        if let has = entry["has_quota"] as? Bool, !has { return nil }

        let entitlement = (entry["entitlement"] as? NSNumber)?.doubleValue
        let remaining = ((entry["remaining"] as? NSNumber)
            ?? (entry["quota_remaining"] as? NSNumber))?.doubleValue

        // Counted, not reported, when both counts are there: they are the exact
        // pair, and `percent_remaining` is rounded off the same division.
        if let entitlement, entitlement > 0, let remaining {
            return clamp((entitlement - remaining) / entitlement * 100)
        }
        if let left = (entry["percent_remaining"] as? NSNumber)?.doubleValue {
            return clamp(100 - left)
        }
        // An entitlement of zero with nothing else said is not a full allowance
        // and not an empty one; it is a kind of allowance this plan does not
        // have, and it is left out.
        return nil
    }

    /// Overage lets a count run past its entitlement, so the division can come
    /// out above 100 or, if the service credits something back, below zero. The
    /// bar is a proportion of a limit and stops at its ends; the fact of going
    /// over is the service's to bill, not this app's to draw.
    private static func clamp(_ percent: Double) -> Double {
        guard percent.isFinite else { return 0 }
        return min(max(percent, 0), 100)
    }

    /// A calendar day, read as midnight UTC.
    ///
    /// The allowance resets on a date rather than at an instant, and the app
    /// wants an instant to count down to. UTC midnight is the one reading that
    /// does not drift with where the reader is standing, which is the same
    /// choice the release dates make.
    private static func reset(_ value: Any?) -> Date? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }
}
