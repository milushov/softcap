import Testing
import Foundation
import ProviderKit
@testable import ZaiProvider

private let planBody = Data(#"""
{"code":200,"success":true,"data":{"level":"pro","limits":[
  {"type":"CREDIT_LIMIT","unit":3,"number":5,"usage":2000,"currentValue":251,
   "nextResetTime":1790256683169}]}}
"""#.utf8)

private actor CheckHTTP: HTTPClient {
    private var replies: [(Data, Int)]
    private(set) var headers: [[String: String]] = []
    init(_ replies: [(Data, Int)]) { self.replies = replies }

    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        #expect(url == ZaiEndpoints.usage)
        self.headers.append(headers)
        return replies.isEmpty ? (Data(), 500) : replies.removeFirst()
    }

    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
        Issue.record("checking a key must not ask a model for anything")
        return (Data(), 500)
    }
}

/// Handing over a key is the whole of signing in here: one request proves it
/// works and says what to call the account.
@Suite struct ZaiKeySignIn {

    @Test func aGoodKeyBecomesAnAccountNamedForItsPlan() async throws {
        let http = CheckHTTP([(planBody, 200)])
        let account = try await ZaiKeyLogin(http: http).account(for: "a-key")

        #expect(account.account.provider == .glm)
        // The plan level, which is all this service says about an account.
        #expect(account.account.lastKnownName == "Pro")
        #expect(account.tokens.accessToken == "a-key")
        // Static: nothing to rotate, which the store reads through
        // `rotatesCredentials`.
        #expect(account.tokens.refreshToken == nil)

        let headers = try #require(await http.headers.first)
        #expect(headers["Authorization"] == "a-key")
    }

    /// The same key is the same account, so giving it twice updates a row
    /// rather than leaving two nobody can tell apart — which matters more here
    /// than anywhere, because the rows are named after a plan and two on one
    /// plan already read alike.
    @Test func theSameKeyLandsOnTheSameAccount() async throws {
        let first = try await ZaiKeyLogin(http: CheckHTTP([(planBody, 200)])).account(for: "a-key")
        let again = try await ZaiKeyLogin(http: CheckHTTP([(planBody, 200)])).account(for: "a-key")
        #expect(first.account.id == again.account.id)

        let other = try await ZaiKeyLogin(http: CheckHTTP([(planBody, 200)])).account(for: "b-key")
        #expect(other.account.id != first.account.id)
    }

    /// The identifier is written to the keychain, read back into snapshots and
    /// printed in diagnostics. The key may appear in none of those.
    @Test func theIdentifierDoesNotCarryTheKey() async throws {
        let key = "a-very-distinctive-key"
        let account = try await ZaiKeyLogin(http: CheckHTTP([(planBody, 200)])).account(for: key)
        #expect(!account.account.id.contains(key))
        #expect(!account.account.handle.contains(key))
        #expect(account.account.handle.count == 16)
        #expect(account.account.id == "glm/\(account.account.handle)")
    }

    /// Surrounding space is what a paste brings with it, not part of the key.
    @Test func aPastedKeyIsTrimmedBeforeItIsUsed() async throws {
        let http = CheckHTTP([(planBody, 200)])
        let account = try await ZaiKeyLogin(http: http).account(for: "  a-key\n")
        #expect(account.tokens.accessToken == "a-key")
        #expect(await http.headers.first?["Authorization"] == "a-key")
    }

    @Test func anEmptyKeyIsRefusedWithoutAskingTheService() async throws {
        let http = CheckHTTP([])
        await #expect(throws: ProviderFailure.self) {
            try await ZaiKeyLogin(http: http).account(for: "   ")
        }
        #expect(await http.headers.isEmpty)
    }

    @Test(arguments: [401, 403])
    func aKeyTheServiceRefusesAsksForAnother(status: Int) async throws {
        do {
            _ = try await ZaiKeyLogin(http: CheckHTTP([(Data(), status)])).account(for: "a-key")
            Issue.record("a refused key must not become an account")
        } catch let failure as ProviderFailure {
            #expect(failure.kind == .needsLogin)
        }
    }

    @Test func aServerFailureIsNotAKeyProblem() async throws {
        do {
            _ = try await ZaiKeyLogin(http: CheckHTTP([(Data(), 503)])).account(for: "a-key")
            Issue.record("a 503 must not become an account")
        } catch let failure as ProviderFailure {
            #expect(failure.kind == .network)
        }
    }

    /// Checked by reading, not merely by fetching. A 200 whose body this app
    /// cannot parse is a key that produces an unreadable row on every poll
    /// from here on, and the moment to find that out is while somebody is
    /// still looking at the field they typed into.
    @Test func aKeyThatFetchesButDoesNotParseIsRefusedNow() async throws {
        let body = Data(#"{"success":true,"data":{"limits":[{"unit":9,"number":9}]}}"#.utf8)
        do {
            _ = try await ZaiKeyLogin(http: CheckHTTP([(body, 200)])).account(for: "a-key")
            Issue.record("an unreadable reply must not become an account")
        } catch let failure as ProviderFailure {
            #expect(failure.kind == .malformed)
        }
    }

    /// And an in-band refusal keeps the kind `parse` gave it.
    @Test func aRevokedKeyReportedInsideATwoHundredStillAsksForAnother() async throws {
        let body = Data(#"{"code":401,"msg":"invalid token","success":false}"#.utf8)
        do {
            _ = try await ZaiKeyLogin(http: CheckHTTP([(body, 200)])).account(for: "a-key")
            Issue.record("a refusal must not become an account")
        } catch let failure as ProviderFailure {
            #expect(failure.kind == .needsLogin)
        }
    }
}
