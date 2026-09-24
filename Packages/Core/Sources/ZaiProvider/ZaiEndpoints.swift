import Foundation
import ProviderKit

/// Where the GLM Coding Plan's quota is read from.
///
/// A first-party endpoint belonging to the web console, not a documented API —
/// the same footing as the three services already read, and the same obligation
/// when it moves. It has moved once already: the entries it returns were
/// `TIME_LIMIT` and `TOKENS_LIMIT` until recently and are `CREDIT_LIMIT` now.
/// `ZaiQuotaResponse` is written not to care, and says why.
public enum ZaiEndpoints {
    public static let usage = URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!

    /// The key, bare.
    ///
    /// No `Bearer`. The prefix every other service here requires is refused by
    /// this one with a 401, which is the most confusing possible way to be
    /// wrong: it reads as a dead key rather than as a malformed header, and the
    /// row would tell somebody to sign in again with a credential that works.
    public static func headers(key: String) -> [String: String] {
        [
            "Authorization": key,
            "Accept": "application/json",
            "Accept-Language": "en-US,en",
        ]
    }
}
