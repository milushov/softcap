import Testing
import Foundation
import ClaudeProvider
import ProviderKit
@testable import Diagnostics

/// Records what a reporter tried to send, so the tests can assert on traffic
/// without any.
actor Wire {
    private(set) var posts: [(url: URL, headers: [String: String], body: Data)] = []
    var status = 200
    var refuses = false

    func setStatus(_ value: Int) { status = value }
    func refuse() { refuses = true }

    func note(url: URL, headers: [String: String], body: Data) throws -> (Data, Int) {
        if refuses { throw ProviderFailure(kind: .network, diagnostic: "offline") }
        posts.append((url, headers, body))
        return (Data(), status)
    }

    var count: Int { posts.count }

    /// `Data`, not a decoded dictionary: `[String: Any]` is not `Sendable` and
    /// cannot leave an actor. The tests decode on their own side.
    var lastBody: Data? { posts.last?.body }
}

struct StubHTTP: HTTPClient {
    let wire: Wire

    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        (Data(), 200)
    }

    func post(
        _ url: URL, headers: [String: String], body: Data
    ) async throws -> (Data, Int) {
        try await wire.note(url: url, headers: headers, body: body)
    }
}

@Suite struct AReportIsShapedTheWayTheCollectorExpects {

    private func reporter(_ wire: Wire) -> CollectorReporter {
        CollectorReporter(
            http: StubHTTP(wire: wire),
            destination: Diagnostics.shipped,
            client: "softcap/1.0"
        )
    }

    private func event(_ message: String = "something failed") -> DiagnosticEvent {
        DiagnosticEvent(
            level: .error, category: "poll", message: message,
            release: "softcap@1.0", environment: "production"
        )
    }

    @Test func theKeyTravelsInTheHeaderTheCollectorReads() async throws {
        let wire = Wire()
        await reporter(wire).send(event())

        let posts = await wire.posts
        let auth = try #require(posts.last?.headers["X-Sentry-Auth"])
        #expect(auth.contains("sentry_version=7"))
        #expect(auth.contains("sentry_key=\(Diagnostics.shipped.key)"))
    }

    @Test func aRefusedStatusIsNotMistakenForDelivery() async {
        let wire = Wire()
        await wire.setStatus(429)
        #expect(await reporter(wire).send(event()) == false)
    }

    /// A collector that cannot be reached must not become a second failure on
    /// top of the one being reported.
    @Test func anUnreachableCollectorIsSwallowed() async {
        let wire = Wire()
        await wire.refuse()
        #expect(await reporter(wire).send(event()) == false)
    }

    @Test func theIdentifierIsThirtyTwoHexCharactersWithoutDashes() {
        let id = DiagnosticEvent.freshID()
        #expect(id.count == 32)
        #expect(!id.contains("-"))
        #expect(id.allSatisfy { $0.isHexDigit })
    }

    /// The scrubber runs when the event is built, so there is no route to the
    /// wire that skips it.
    @Test func anEventCannotBeBuiltCarryingASecret() async throws {
        let wire = Wire()
        let home = "/Users/" + "someone"
        let key = "sk-ant-" + "api03-XYZ123abcdef"
        await reporter(wire).send(event("failed for \(home) with \(key)"))

        let body = try #require(await wire.lastBody)
        let json = String(decoding: body, as: UTF8.self)
        #expect(!json.contains("someone"))
        #expect(!json.contains("api03-XYZ123"))
    }
}

@Suite struct NothingIsReportedUntilItIsTurnedOn {

    private func wired(enabled: Bool) async -> (Diagnostics, Wire) {
        let wire = Wire()
        let diagnostics = Diagnostics()
        await diagnostics.start(
            reporter: CollectorReporter(
                http: StubHTTP(wire: wire), destination: Diagnostics.shipped,
                client: "softcap/test"),
            release: "softcap@1.0",
            enabled: enabled
        )
        return (diagnostics, wire)
    }

    @Test func aStoppedInstanceSendsNothing() async {
        let (diagnostics, wire) = await wired(enabled: false)
        await diagnostics.report(.error, category: "poll", message: "boom")
        #expect(await wire.count == 0)
    }

    @Test func aStartedInstanceSends() async {
        let (diagnostics, wire) = await wired(enabled: true)
        await diagnostics.report(.error, category: "poll", message: "boom")
        #expect(await wire.count == 1)
    }

    /// The setting can be switched off while the app is running, and the next
    /// report has to notice rather than the next launch.
    @Test func turningItOffStopsTheVeryNextReport() async {
        let (diagnostics, wire) = await wired(enabled: true)
        await diagnostics.report(.error, category: "poll", message: "one")
        await diagnostics.setEnabled(false)
        await diagnostics.report(.error, category: "poll", message: "two")
        #expect(await wire.count == 1)
    }

    /// Never configured at all is the state every test process is in, and the
    /// state a debug build stays in.
    @Test func anInstanceThatWasNeverStartedIsInert() async {
        let diagnostics = Diagnostics()
        #expect(await diagnostics.isEnabled == false)
        #expect(await diagnostics.report(.error, category: "poll", message: "boom") == false)
    }

    @Test func aProviderFailureReportsItsKindAndDiagnostic() async throws {
        let (diagnostics, wire) = await wired(enabled: true)
        await diagnostics.report(
            ProviderFailure(kind: .malformed, diagnostic: "profile not parsed"),
            category: "claude"
        )
        let data = try #require(await wire.lastBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let exception = try #require(body["exception"] as? [String: Any])
        let values = try #require(exception["values"] as? [[String: Any]])
        #expect(values.first?["type"] as? String == "ProviderFailure.malformed")
        #expect((body["message"] as? [String: Any])?["formatted"] as? String == "profile not parsed")
    }
}
