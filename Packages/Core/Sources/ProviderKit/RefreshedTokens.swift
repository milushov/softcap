import Foundation

public struct RefreshedTokens: Sendable, Hashable {
    public let accessToken: String
    public let refreshToken: String?
    /// How many seconds the access token is good for, as the server reported it,
    /// or `nil` when the reply did not say.
    ///
    /// `nil` means nothing may be assumed. A guessed lifetime would have the app
    /// handing out a token the server had already retired, and that failure
    /// arrives looking like a dead account rather than like a guess.
    public let expiresIn: TimeInterval?

    public init(
        accessToken: String, refreshToken: String?, expiresIn: TimeInterval? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
    }
}

