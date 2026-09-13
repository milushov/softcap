import Testing
import Foundation
import ProviderKit

/// App Review rejected the store build automatically on 2026-09-14, saying the
/// `com.apple.security.network.server` entitlement "does not appear to have
/// matching functionality". The obvious reading of that letter is to delete the
/// key, and deleting it breaks signing in: the sandbox denies the loopback bind
/// without it, so the redirect the provider sends the browser to has nowhere to
/// land. Claude would fall back to pasting the code by hand; Codex, which has no
/// manual redirect, would lose sign-in altogether.
///
/// So the letter is answered rather than obeyed — `docs/APP-REVIEW-NETWORK-SERVER.md`
/// holds the reply — and this suite stands between the next reader of that letter
/// and the key. It also states the other half honestly: the entitlement is
/// justified only while the redirect is a loopback one. If the providers ever
/// register a redirect that is not, these checks are what should be changed, and
/// the key should go with them.
@Suite struct TheLoopbackEntitlementIsEarned {

    /// The sandboxed lane carries the key. Measured before it was defended: the
    /// same `NWListener` call in a sandboxed bundle without it fails with POSIX 1,
    /// "Operation not permitted", and with it reaches `.ready`.
    @Test func theStoreBuildCarriesTheServerEntitlement() throws {
        let store = try Self.entitlements("App/Softcap.AppStore.entitlements")
        #expect(store["com.apple.security.app-sandbox"] as? Bool == true,
                "the store build is not sandboxed; upload validation refuses that")
        #expect(store["com.apple.security.network.server"] as? Bool == true, """
            the store build lost com.apple.security.network.server. App Review asks \
            for this and the app cannot sign in without it — read \
            docs/APP-REVIEW-NETWORK-SERVER.md before removing it again
            """)
        #expect(store["com.apple.security.network.client"] as? Bool == true,
                "the app talks to the providers over HTTPS")
    }

    /// Only the lane that needs it. Nothing else in the tree asks to listen:
    /// the GitHub build is unsandboxed, so no entitlement grants it anything,
    /// and the widget draws a number it reads from a file.
    @Test func nothingElseAsksToListen() throws {
        for file in ["App/Softcap.entitlements",
                     "Widget/SoftcapWidget.entitlements",
                     "iOS/SoftcapiOS.entitlements",
                     "iOSWidget/SoftcapiOSWidget.entitlements"] {
            let entitlements = try Self.entitlements(file)
            #expect(entitlements["com.apple.security.network.server"] == nil,
                    "\(file) asks to listen, and nothing in it does")
        }
    }

    /// The functionality the entitlement is for, named where it lives. A reviewer
    /// is told to look at this file; an empty or renamed one makes the reply false.
    @Test func theListenerIsStillBoundToTheLoopback() throws {
        let listener = try Self.source("App/BrowserCallbackListener.swift")
        #expect(listener.contains("NWListener"),
                "the OAuth callback no longer uses NWListener; the reply to App Review names it")
        #expect(listener.contains(".ipv4(.loopback)"), """
            the OAuth callback listener is no longer pinned to the loopback. Either \
            fix that, or the entitlement is asking for more than the app deserves
            """)
    }

    /// And the redirect the provider is asked to send the browser to is still a
    /// loopback URI — the reason an incoming connection has to be accepted at all.
    @Test func theRedirectTheProvidersAreGivenIsStillLoopback() {
        let redirect = StubAuthentication().localRedirect(port: 54545)
        #expect(redirect == "http://localhost:54545/callback",
                "the redirect is no longer a loopback address; the entitlement rests on that")
    }

    /// The reply exists where the entitlements file says it does, and says what it
    /// is for. App Review asks for this in writing on every submission that trips
    /// the same automated check.
    @Test func theReplyToAppReviewIsWhereItIsPromised() throws {
        let reply = try Self.source("docs/APP-REVIEW-NETWORK-SERVER.md")
        #expect(reply.contains("com.apple.security.network.server"),
                "the reply no longer names the entitlement it is about")
        #expect(reply.contains("App Review Information"),
                "the reply no longer says where in App Store Connect the text goes")

        let file = try Self.source("App/Softcap.AppStore.entitlements")
        #expect(file.contains("docs/APP-REVIEW-NETWORK-SERVER.md"),
                "the entitlements file no longer sends its reader to the reply")
    }

    // MARK: - reading the tree

    private static func entitlements(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent(path))
        let plist = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil)
        return try #require(plist as? [String: Any], "\(path) is not a dictionary")
    }

    private static func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private static var root: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
}

/// The protocol's own `localRedirect`, exercised through the smallest thing that
/// can conform: the default implementation is what every provider gets.
private struct StubAuthentication: BrowserAuthenticating {
    let provider: ProviderID = .claude
    let callbackPath = "/callback"
    let callbackPort: UInt16? = nil
    let manualRedirectURI: String? = nil

    func authorizationURL(
        redirectURI: String, pkce: PKCEPair, state: String, manual: Bool
    ) -> URL {
        URL(string: redirectURI) ?? URL(fileURLWithPath: "/")
    }

    func authenticate(
        code: String, verifier: String, redirectURI: String, state: String
    ) async throws -> AuthenticatedAccount {
        throw ProviderFailure(kind: .network, diagnostic: "stub")
    }
}
