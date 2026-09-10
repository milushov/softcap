import Foundation

/// The server has finished with this refresh token: expired, revoked, or rotated
/// away by another client. Distinct from any other refresh failure because the
/// answer will not change — a network error is worth retrying in five minutes and
/// this is not, and a client that asks forever with a credential it has been told
/// is dead is a badly behaved one.
public struct RefreshRejected: Error, Sendable, Equatable {
    public init() {}
}

