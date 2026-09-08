import Foundation
import ProviderKit

/// Remembers what an account is called, so the name is not re-fetched on every
/// poll.
///
/// The provider is a value rebuilt before each poll, so this has to live outside
/// it. Two reasons it exists at all:
///
/// A poll runs as often as once a minute, and it asked the profile endpoint each
/// time for an address and a plan name that change about never — doubling the
/// requests for an answer already known.
///
/// And a single failed profile read dropped the row's name to `claude/<uuid>`,
/// which on screen reads as a different account rather than the same one with a
/// hiccup. A remembered name survives the hiccup.
///
/// The entry expires, because a plan can be upgraded and a name is not
/// permanent — just far more permanent than a minute.
public actor ClaudeIdentityCache {
    public struct Identity: Sendable, Hashable {
        public let displayName: String
        public let planLabel: String

        public init(displayName: String, planLabel: String) {
            self.displayName = displayName
            self.planLabel = planLabel
        }
    }

    /// Long enough that a poll never pays for it, short enough that a plan
    /// change shows up the same day.
    public static let lifetime: TimeInterval = 6 * 60 * 60

    private var entries: [String: (identity: Identity, at: Date)] = [:]
    private let lifetime: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        lifetime: TimeInterval = ClaudeIdentityCache.lifetime,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.lifetime = lifetime
        self.now = now
    }

    public func identity(for accountID: String) -> Identity? {
        guard let entry = entries[accountID] else { return nil }
        guard now().timeIntervalSince(entry.at) < lifetime else {
            entries[accountID] = nil
            return nil
        }
        return entry.identity
    }

    public func remember(_ profile: ClaudeProfile, for accountID: String) {
        entries[accountID] = (
            Identity(displayName: profile.displayName, planLabel: profile.planLabel), now()
        )
    }

    /// Forgetting an account should forget what it was called, too.
    public func forget(_ accountID: String) { entries[accountID] = nil }
}
