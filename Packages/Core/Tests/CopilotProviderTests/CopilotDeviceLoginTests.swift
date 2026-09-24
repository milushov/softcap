import Testing
import Foundation
import ProviderKit
@testable import CopilotProvider

private let codeBody = Data(#"""
{"device_code":"dev-1","user_code":"WDJB-MJHT","verification_uri":"https://github.com/login/device",
 "expires_in":900,"interval":5}
"""#.utf8)

private let identityBody = Data(#"{"id":4711,"login":"sam","name":"Sam"}"#.utf8)

/// Answers by address, because this flow talks to three of them and the order
/// it talks to them in is part of what is being tested.
private actor FlowHTTP: HTTPClient {
    private var posts: [URL: [(Data, Int)]]
    private var gets: [URL: [(Data, Int)]]
    private(set) var postBodies: [(URL, String)] = []
    private(set) var getHeaders: [(URL, [String: String])] = []

    init(posts: [URL: [(Data, Int)]] = [:], gets: [URL: [(Data, Int)]] = [:]) {
        self.posts = posts
        self.gets = gets
    }

    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        getHeaders.append((url, headers))
        guard var queue = gets[url], !queue.isEmpty else { return (Data(), 500) }
        let head = queue.removeFirst()
        gets[url] = queue
        return head
    }

    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
        postBodies.append((url, String(decoding: body, as: UTF8.self)))
        #expect(headers["Accept"] == "application/json")
        guard var queue = posts[url], !queue.isEmpty else { return (Data(), 500) }
        let head = queue.removeFirst()
        posts[url] = queue
        return head
    }
}

private func json(_ text: String) -> Data { Data(text.utf8) }

private let epoch = Date(timeIntervalSince1970: 1_800_000_000)

@Suite struct CopilotDeviceSignIn {

    private func login(_ http: FlowHTTP) -> CopilotDeviceLogin {
        CopilotDeviceLogin(http: http, now: { epoch })
    }

    @Test func asksForACodeAndAPageToTypeItInto() async throws {
        let http = FlowHTTP(posts: [CopilotEndpoints.deviceCode: [(codeBody, 200)]])
        let grant = try await login(http).requestCode()

        #expect(grant.userCode == "WDJB-MJHT")
        #expect(grant.deviceCode == "dev-1")
        #expect(grant.verificationURL.absoluteString == "https://github.com/login/device")
        #expect(grant.interval == 5)
        #expect(grant.expiresAt == epoch.addingTimeInterval(900))

        let (url, body) = try #require(await http.postBodies.first)
        #expect(url == CopilotEndpoints.deviceCode)
        #expect(body.contains("client_id=\(CopilotEndpoints.clientID)"))
        #expect(body.contains("scope=read%3Auser"))
    }

    /// Both have defaults in the specification, and a reply that leaves them
    /// out is not a broken reply.
    @Test func aSilentIntervalAndDeadlineTakeTheSpecifiedDefaults() async throws {
        let http = FlowHTTP(posts: [CopilotEndpoints.deviceCode: [(json(#"""
            {"device_code":"d","user_code":"U","verification_uri":"https://github.com/login/device"}
            """#), 200)]])
        let grant = try await login(http).requestCode()
        #expect(grant.interval == 5)
        #expect(grant.expiresAt == epoch.addingTimeInterval(900))
    }

    @Test func anIncompleteCodeReplyIsMalformed() async throws {
        let http = FlowHTTP(posts: [CopilotEndpoints.deviceCode: [(json(#"{"user_code":"U"}"#), 200)]])
        await #expect(throws: ProviderFailure.self) { try await login(http).requestCode() }
    }

    @Test func aRefusedCodeRequestIsNetwork() async throws {
        let http = FlowHTTP(posts: [CopilotEndpoints.deviceCode: [(Data(), 500)]])
        do {
            _ = try await login(http).requestCode()
            Issue.record("a 500 must not produce a grant")
        } catch let failure as ProviderFailure {
            #expect(failure.kind == .network)
        }
    }

    // MARK: - polling

    private var grant: DeviceCodeGrant {
        DeviceCodeGrant(
            deviceCode: "dev-1", userCode: "WDJB-MJHT",
            verificationURL: URL(string: "https://github.com/login/device")!,
            interval: 5, expiresAt: epoch.addingTimeInterval(900))
    }

    private func poll(_ reply: Data, status: Int = 200) async throws -> DeviceCodePoll {
        let http = FlowHTTP(posts: [CopilotEndpoints.token: [(reply, status)]])
        return try await login(http).poll(grant)
    }

    /// The whole state machine arrives with a 200 and a word in `error`, so the
    /// status alone decides nothing.
    @Test func nobodyHasTypedItYet() async throws {
        guard case .pending = try await poll(json(#"{"error":"authorization_pending"}"#)) else {
            Issue.record("a pending reply must not end the attempt")
            return
        }
    }

    @Test func beingToldOffRaisesTheInterval() async throws {
        guard case .slowDown(let interval) =
                try await poll(json(#"{"error":"slow_down","interval":10}"#)) else {
            Issue.record("slow_down must change the interval")
            return
        }
        #expect(interval == 10)
    }

    /// The service raises it; if it declines to say by how much, the attempt
    /// raises it itself rather than asking again at the rate it was refused at.
    @Test func aSilentSlowDownStillSlowsDown() async throws {
        guard case .slowDown(let interval) = try await poll(json(#"{"error":"slow_down"}"#)) else {
            Issue.record("slow_down must change the interval")
            return
        }
        #expect(interval > grant.interval)
    }

    @Test func theyPressedNo() async throws {
        await #expect(throws: DeviceCodeRejected(reason: .denied)) {
            try await poll(json(#"{"error":"access_denied"}"#))
        }
    }

    @Test func theCodeWentStaleBeforeTheyGotToIt() async throws {
        await #expect(throws: DeviceCodeRejected(reason: .expired)) {
            try await poll(json(#"{"error":"expired_token"}"#))
        }
    }

    @Test func anUnknownRefusalAsksForASignInRatherThanLooping() async throws {
        do {
            _ = try await poll(json(#"{"error":"unsupported_grant_type"}"#))
            Issue.record("an unknown refusal must end the attempt")
        } catch let failure as ProviderFailure {
            #expect(failure.kind == .needsLogin)
        }
    }

    // MARK: - the grant

    @Test func aGrantedCodeBecomesAnAccount() async throws {
        let http = FlowHTTP(
            posts: [CopilotEndpoints.token: [(json(#"{"access_token":"tok","token_type":"bearer"}"#), 200)]],
            gets: [CopilotEndpoints.identity: [(identityBody, 200)]])

        guard case .granted(let account) = try await login(http).poll(grant) else {
            Issue.record("an access token must end the attempt")
            return
        }

        // Filed under the number, shown by the login: the login is the owner's
        // to change, and a renamed account must not arrive as a second one.
        #expect(account.account.id == "copilot/4711")
        #expect(account.account.handle == "4711")
        #expect(account.account.lastKnownName == "sam")
        #expect(account.account.provider == .copilot)
        #expect(account.tokens.accessToken == "tok")
        // The ordinary case for this client: nothing to rotate, which is what
        // `ProviderID.rotatesCredentials` exists to interpret.
        #expect(account.tokens.refreshToken == nil)
        #expect(account.tokens.expiresIn == nil)

        let (_, body) = try #require(await http.postBodies.first)
        #expect(body.contains("device_code=dev-1"))
        #expect(body.contains("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code"))

        let (url, headers) = try #require(await http.getHeaders.first)
        #expect(url == CopilotEndpoints.identity)
        #expect(headers["Authorization"] == "Bearer tok")
    }

    /// When the client is configured to expire tokens the reply says so, and
    /// the ordinary refreshing path takes over. The behaviour follows the
    /// reply rather than an assumption about it.
    @Test func anExpiringGrantIsCarriedThroughIntact() async throws {
        let http = FlowHTTP(
            posts: [CopilotEndpoints.token: [(json(#"""
                {"access_token":"tok","refresh_token":"ref","expires_in":28800}
                """#), 200)]],
            gets: [CopilotEndpoints.identity: [(identityBody, 200)]])

        guard case .granted(let account) = try await login(http).poll(grant) else {
            Issue.record("an access token must end the attempt")
            return
        }
        #expect(account.tokens.refreshToken == "ref")
        #expect(account.tokens.expiresIn == 28800)
    }

    @Test func aLoginlessIdentityFallsBackToTheNumber() async throws {
        let http = FlowHTTP(
            posts: [CopilotEndpoints.token: [(json(#"{"access_token":"tok"}"#), 200)]],
            gets: [CopilotEndpoints.identity: [(json(#"{"id":4711}"#), 200)]])

        guard case .granted(let account) = try await login(http).poll(grant) else {
            Issue.record("an access token must end the attempt")
            return
        }
        #expect(account.account.lastKnownName == "4711")
    }

    @Test func anIdentityWithoutAnIdIsMalformed() async throws {
        let http = FlowHTTP(
            posts: [CopilotEndpoints.token: [(json(#"{"access_token":"tok"}"#), 200)]],
            gets: [CopilotEndpoints.identity: [(json(#"{"login":"sam"}"#), 200)]])
        do {
            _ = try await login(http).poll(grant)
            Issue.record("an identity with no id must not produce an account")
        } catch let failure as ProviderFailure {
            #expect(failure.kind == .malformed)
        }
    }

    @Test func aRefusedIdentityAsksForASignIn() async throws {
        let http = FlowHTTP(
            posts: [CopilotEndpoints.token: [(json(#"{"access_token":"tok"}"#), 200)]],
            gets: [CopilotEndpoints.identity: [(Data(), 401)]])
        do {
            _ = try await login(http).poll(grant)
            Issue.record("a 401 must not produce an account")
        } catch let failure as ProviderFailure {
            #expect(failure.kind == .needsLogin)
        }
    }
}
