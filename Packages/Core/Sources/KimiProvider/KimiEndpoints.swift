import Foundation
import ProviderKit

/// Where a Kimi Code subscription's quota is read from.
///
/// Two hosts answer it and a key belongs to one of them: `api.kimi.com/coding`
/// is the Coding Plan's own, and `api.moonshot.ai` is the general Moonshot API.
/// Which one a person's key works with is not something the key says, so it is
/// found out once — at sign-in, by trying — and remembered in the account's
/// handle, which is what `AccountRef.handle` is for: "whatever the provider
/// navigates by".
///
/// The alternative was trying both on every poll, which for everybody on the
/// second host is a wasted request every five minutes, forever.
public enum KimiEndpoints {
    public enum Region: String, Sendable, CaseIterable {
        /// The Coding Plan's own host, tried first because `/usages` is a
        /// Coding Plan endpoint before it is a Moonshot one.
        case coding
        case moonshot

        var base: URL {
            switch self {
            case .coding:   URL(string: "https://api.kimi.com/coding/v1")!
            case .moonshot: URL(string: "https://api.moonshot.ai/v1")!
            }
        }

        var usage: URL { base.appendingPathComponent("usages") }
    }

    /// The handle a region and a key make together, and the pair it comes back
    /// as. The region is a prefix rather than a field because there is nowhere
    /// to put a field: what is saved is an identifier and a credential.
    public static func handle(_ region: Region, _ digest: String) -> String {
        "\(region.rawValue)-\(digest)"
    }

    public static func region(ofHandle handle: String) -> Region {
        guard let separator = handle.firstIndex(of: "-"),
              let named = Region(rawValue: String(handle[handle.startIndex..<separator]))
        else {
            // A handle written before regions were, or one this build cannot
            // read. The Coding Plan's host is the one to guess at, and a wrong
            // guess costs a refused request rather than a wrong number.
            return .coding
        }
        return named
    }

    /// `Bearer`, unlike the other key-based service here, which refuses the
    /// prefix with a 401. Two services taking a key and disagreeing about the
    /// header is the kind of thing that is obvious once and invisible after.
    public static func headers(key: String) -> [String: String] {
        ["Authorization": "Bearer \(key)", "Accept": "application/json"]
    }
}
