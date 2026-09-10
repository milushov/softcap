import Foundation

/// Provider-specific policy; the app owns the browser and loopback listener.
public protocol BrowserAuthenticating: Sendable {
    var provider: ProviderID { get }
    var callbackPath: String { get }
    var callbackPort: UInt16? { get }
    var manualRedirectURI: String? { get }
    func authorizationURL(redirectURI: String, pkce: PKCEPair, state: String, manual: Bool) -> URL
    func authenticate(
        code: String, verifier: String, redirectURI: String, state: String
    ) async throws -> AuthenticatedAccount
}

public extension BrowserAuthenticating {
    func localRedirect(port: UInt16) -> String? {
        guard port != 0, callbackPort == nil || callbackPort == port else { return nil }
        return "http://localhost:\(port)\(callbackPath)"
    }
}

public struct AuthenticatedAccount: Sendable {
    public let account: AccountRef
    public let tokens: RefreshedTokens

    public init(account: AccountRef, tokens: RefreshedTokens) {
        self.account = account
        self.tokens = tokens
    }
}

/// A complete reference prevents equal handles at different services from
/// selecting, refreshing or invalidating each other's credentials.
public protocol AccountTokenSource: Sendable {
    func accessToken(for account: AccountRef) async throws -> String
    func invalidateAccessToken(for account: AccountRef, rejectedToken: String) async
}
