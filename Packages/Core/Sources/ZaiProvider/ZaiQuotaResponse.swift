import Foundation
import ProviderKit

/// What the service says about a plan and what is left of its windows.
public struct ZaiQuotaResponse: Sendable, Hashable {
    public let planLabel: String
    public let windows: [LimitWindow]

    /// A window is identified by the pair, not by `type`, and not by `unit`
    /// alone.
    ///
    /// **Not `type`.** It read `TOKENS_LIMIT` and `TIME_LIMIT` until recently
    /// and reads `CREDIT_LIMIT` now. Every reader that keyed on it dropped the
    /// new entries and drew zeros — a schema change turned into a confident
    /// statement about somebody's account, which is the one failure this app
    /// treats as worse than showing nothing.
    ///
    /// **Not `unit` alone.** `unit` is the unit of time and `number` is how
    /// many: `(3, 5)` is five hours, `(6, 1)` is one week. Keying on the unit
    /// would file a one-hour window as `session`, and `session` is labelled
    /// `5h` in ten catalogues — a wrong period stated confidently beside a
    /// right number. The pair says exactly which window this is.
    ///
    /// Anything else is skipped rather than guessed at. The legacy shape
    /// carried `(5, 1)` for a monthly allowance over MCP tools, which is not
    /// one of this app's two windows and is not made into one.
    private static let known: [Pair: String] = [
        Pair(unit: 3, number: 5): "session",
        Pair(unit: 6, number: 1): "weekly",
    ]

    private struct Pair: Hashable {
        let unit: Int
        let number: Int
    }

    /// The order a row draws them in: the short window first, as every other
    /// row here does.
    private static let order = ["session", "weekly"]

    public static func parse(_ data: Data) throws -> ZaiQuotaResponse {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderFailure(kind: .malformed, diagnostic: "usage reply is not an object")
        }

        // A 200 carrying `success: false` is this service saying no inside an
        // envelope that looks like yes, and the reason is in `code` rather than
        // in the status. A revoked key arrives this way — and `malformed` would
        // put "the reply could not be read" on the one failure a person can
        // actually fix, because every screen gates the way back in on
        // `needsLogin`: the row's offer, the minimal row's, the window's and
        // the Accounts list's. Read the code the envelope already carries.
        if let succeeded = flag(root["success"]), !succeeded {
            let said = (root["msg"] as? String) ?? "no reason given"
            let code = whole(root["code"])
            throw ProviderFailure(
                kind: code == 401 || code == 403 ? .needsLogin : .malformed,
                diagnostic: "usage refused (\(code.map(String.init) ?? "no code")): \(said)")
        }

        guard let payload = root["data"] as? [String: Any],
              let listed = payload["limits"] as? [Any] else {
            throw ProviderFailure(kind: .malformed, diagnostic: "usage reply has no limits")
        }

        // Entry by entry, not the array in one cast. `as? [[String: Any]]` is
        // all-or-nothing: one entry of a shape this app has not met takes both
        // real windows down with it, and this service is in the middle of
        // changing what its entries look like. An entry that is not an object
        // is skipped like any other one that cannot be read.
        let entries = listed.compactMap { $0 as? [String: Any] }

        var found: [String: LimitWindow] = [:]
        for entry in entries {
            guard let unit = (entry["unit"] as? NSNumber)?.intValue,
                  let number = (entry["number"] as? NSNumber)?.intValue,
                  let id = known[Pair(unit: unit, number: number)],
                  let percent = used(entry) else { continue }
            // First wins. A reply listing the same window twice is a reply we
            // do not understand well enough to pick between them, and taking
            // the later one silently would make which is drawn depend on the
            // order the service happened to serialise.
            if found[id] == nil {
                found[id] = LimitWindow(id: id, percent: percent, resetsAt: reset(entry))
            }
        }

        let windows = order.compactMap { found[$0] }
        guard !windows.isEmpty else {
            throw ProviderFailure(
                kind: .malformed,
                diagnostic: "usage reply held \(listed.count) limits and no window this app knows")
        }

        return ZaiQuotaResponse(plan: payload["level"], windows: windows)
    }

    private init(plan level: Any?, windows: [LimitWindow]) {
        // The service's own word for the plan, capitalised and not invented. A
        // dash when it does not say, as every other row without a plan shows.
        let named = (level as? String).flatMap { $0.isEmpty ? nil : $0.capitalized }
        self.planLabel = named ?? "—"
        self.windows = windows
    }

    /// How full a window is.
    ///
    /// `usage` is the allowance and `currentValue` is what has gone. The names
    /// are the wrong way round from what they look like, and the obvious
    /// reading — `usage` as usage — produces a row that is plausible and wrong
    /// in both directions at once: nearly empty when it is nearly full.
    ///
    /// Counted from the pair when both are there, because they are exact.
    /// `percentage` is the same division already floored to a whole number and
    /// serves only when the counts do not.
    private static func used(_ entry: [String: Any]) -> Double? {
        let allowance = (entry["usage"] as? NSNumber)?.doubleValue
        let spent = (entry["currentValue"] as? NSNumber)?.doubleValue

        // Stated as zero, this window is one the plan does not have — the same
        // thing `entitlement: 0` means for Copilot. Falling through to
        // `percentage` here would draw a bar reading nought beside a window
        // that has no limit, which is the row of noughts this file refuses.
        // Absent is different: it says nothing, and the reported share serves.
        if let allowance, allowance <= 0 { return nil }

        if let allowance, let spent {
            return clamp(spent / allowance * 100)
        }
        if let reported = (entry["percentage"] as? NSNumber)?.doubleValue {
            return clamp(reported)
        }
        return nil
    }

    /// A share that is not a number is not a share.
    ///
    /// This returned `0` for anything non-finite, which drew the window at
    /// nought — the confident zero this file refuses three times in its own
    /// comments, arrived at by the one path that was not looking.
    ///
    /// No reply can reach it today: `JSONSerialization` refuses a document
    /// holding an overflowing literal rather than handing back an infinity, and
    /// the division above cannot produce a NaN now that a zero allowance is
    /// turned away before it. Kept because the cost is a word and the failure
    /// it guards against is the one that looks like good news.
    private static func clamp(_ percent: Double) -> Double? {
        guard percent.isFinite else { return nil }
        return min(max(percent, 0), 100)
    }

    /// The envelope's own fields, read whatever JSON kind they arrive as.
    ///
    /// Only these two. A refusal that came back as `"success": "false"` would
    /// otherwise skip the block above, fall through to the `limits` guard and
    /// land on `malformed` — so a revoked key would read "the reply could not
    /// be read" and no screen would offer the way back in, which is exactly
    /// what that block exists to prevent. `unit` and `number` stay strict on
    /// purpose: a string there skips the window, and a skipped window is a
    /// visible failure rather than a silent number.
    private static func flag(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let text = value as? String { return Bool(text.lowercased()) }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }

    private static func whole(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }

    /// `nextResetTime` is epoch milliseconds. Read as seconds it lands fifty
    /// thousand years out, and the row would say the limit resets in never.
    private static func reset(_ entry: [String: Any]) -> Date? {
        guard let milliseconds = (entry["nextResetTime"] as? NSNumber)?.doubleValue,
              milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }
}
