import Testing
@testable import ClaudeProvider

@Suite struct LocalRedirect {

    @Test func buildsTheAddressForABoundPort() {
        #expect(OAuthEndpoints.localRedirect(port: 54545) == "http://localhost:54545/callback")
    }

    /// The failure this exists for: zero is both "give me any free port" and
    /// what `NWListener` reports before it is listening, so it reaches the
    /// browser as a real address and the service rejects the sign-in.
    @Test func refusesPortZero() {
        #expect(OAuthEndpoints.localRedirect(port: 0) == nil)
    }

    @Test func acceptsTheEndsOfTheRange() {
        #expect(OAuthEndpoints.localRedirect(port: 1) == "http://localhost:1/callback")
        #expect(OAuthEndpoints.localRedirect(port: 65535) == "http://localhost:65535/callback")
    }
}
