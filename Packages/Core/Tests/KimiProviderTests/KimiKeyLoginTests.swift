import Testing
import Foundation
import ProviderKit
@testable import KimiProvider

private let usagesBody = Data(#"""
{"usages":{"limit_5h":{"used_ratio":0.1,"reset_time":"2026-09-20T18:32:31Z"},
           "limit_7d":{"used_ratio":0.2,"reset_time":"2026-09-22T07:32:31Z"}}}
"""#.utf8)

/// Answers per host, so which one takes the key can be scripted.
private actor HostHTTP: HTTPClient {
    private var replies: [URL: (Data, Int)]
    private(set) var asked: [URL] = []
    private(set) var headers: [[String: String]] = []

    init(_ replies: [KimiEndpoints.Region: (Data, Int)]) {
        self.replies = Dictionary(
            uniqueKeysWithValues: replies.map { ($0.key.usage, $0.value) })
    }

    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        asked.append(url)
        self.headers.append(headers)
        return replies[url] ?? (Data(), 404)
    }

    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
        Issue.record("checking a key must not ask a model for anything")
        return (Data(), 500)
    }
}

@Suite struct KimiKeySignIn {

    @Test(arguments: KimiEndpoints.Region.allCases)
    func whicheverHostTakesTheKeyIsTheOneRemembered(
        region: KimiEndpoints.Region
    ) async throws {
        let http = HostHTTP([region: (usagesBody, 200)])
        let account = try await KimiKeyLogin(http: http, accountName: "Kimi Code")
            .account(for: "sk-kimi-key")

        #expect(account.account.provider == .kimi)
        #expect(KimiEndpoints.region(ofHandle: account.account.handle) == region)
        #expect(account.account.lastKnownName == "Kimi Code")
        #expect(account.tokens.accessToken == "sk-kimi-key")
        // Static: nothing to rotate, which the store reads through
        // `rotatesCredentials`.
        #expect(account.tokens.refreshToken == nil)
        #expect(await http.headers.last?["Authorization"] == "Bearer sk-kimi-key")
    }

    /// The first host is tried first, and a key it takes ends the search.
    @Test func theSecondHostIsNotAskedWhenTheFirstAnswers() async throws {
        let http = HostHTTP([.coding: (usagesBody, 200), .moonshot: (usagesBody, 200)])
        _ = try await KimiKeyLogin(http: http).account(for: "sk-kimi-key")
        #expect(await http.asked == [KimiEndpoints.Region.coding.usage])
    }

    @Test func theSameKeyLandsOnTheSameAccount() async throws {
        let first = try await KimiKeyLogin(http: HostHTTP([.coding: (usagesBody, 200)]))
            .account(for: "sk-kimi-key")
        let again = try await KimiKeyLogin(http: HostHTTP([.coding: (usagesBody, 200)]))
            .account(for: "sk-kimi-key")
        #expect(first.account.id == again.account.id)

        let other = try await KimiKeyLogin(http: HostHTTP([.coding: (usagesBody, 200)]))
            .account(for: "sk-kimi-other")
        #expect(other.account.id != first.account.id)
    }

    /// The identifier reaches the keychain, the shared snapshot and the
    /// diagnostics. The key may reach none of them.
    @Test func theIdentifierDoesNotCarryTheKey() async throws {
        let key = "sk-kimi-a-very-distinctive-key"
        let account = try await KimiKeyLogin(http: HostHTTP([.coding: (usagesBody, 200)]))
            .account(for: key)
        #expect(!account.account.id.contains(key))
        #expect(!account.account.handle.contains(key))
    }

    @Test func aPastedKeyIsTrimmedBeforeItIsUsed() async throws {
        let http = HostHTTP([.coding: (usagesBody, 200)])
        let account = try await KimiKeyLogin(http: http).account(for: "  sk-kimi-key\n")
        #expect(account.tokens.accessToken == "sk-kimi-key")
        #expect(await http.headers.first?["Authorization"] == "Bearer sk-kimi-key")
    }

    @Test func anEmptyKeyIsRefusedWithoutAskingEitherHost() async throws {
        let http = HostHTTP([:])
        await #expect(throws: ProviderFailure.self) {
            try await KimiKeyLogin(http: http).account(for: "  ")
        }
        #expect(await http.asked.isEmpty)
    }

    @Test func aKeyBothHostsRefuseAsksForAnother() async throws {
        let http = HostHTTP([.coding: (Data(), 401), .moonshot: (Data(), 401)])
        do {
            _ = try await KimiKeyLogin(http: http).account(for: "sk-kimi-key")
            Issue.record("a refused key must not become an account")
        } catch let failure as ProviderFailure {
            #expect(failure.kind == .needsLogin)
        }
        // Both were tried: a key refused by one host may belong to the other.
        #expect(await http.asked.count == KimiEndpoints.Region.allCases.count)
    }

    /// A host that was down is not a key that is wrong. Sending somebody after
    /// a new credential because a server was unreachable sends them after the
    /// one thing that was never the problem.
    @Test func aHostThatWasUnreachableIsNotABadKey() async throws {
        let http = HostHTTP([.coding: (Data(), 503), .moonshot: (Data(), 503)])
        do {
            _ = try await KimiKeyLogin(http: http).account(for: "sk-kimi-key")
            Issue.record("an unreachable host must not produce an account")
        } catch let failure as ProviderFailure {
            #expect(failure.kind == .network)
        }
    }

    /// One host down and the other refusing is still not a verdict on the key.
    @Test func oneHostDownAndOneRefusingIsNotAVerdict() async throws {
        let http = HostHTTP([.coding: (Data(), 503), .moonshot: (Data(), 401)])
        do {
            _ = try await KimiKeyLogin(http: http).account(for: "sk-kimi-key")
            Issue.record("this must not produce an account")
        } catch let failure as ProviderFailure {
            #expect(failure.kind == .network)
        }
    }

    /// And a host that was down first does not stop the one that works.
    @Test func aHostThatWasDownDoesNotHideTheOneThatWorks() async throws {
        let http = HostHTTP([.coding: (Data(), 503), .moonshot: (usagesBody, 200)])
        let account = try await KimiKeyLogin(http: http).account(for: "sk-kimi-key")
        #expect(KimiEndpoints.region(ofHandle: account.account.handle) == .moonshot)
    }

    /// Checked by reading, not by fetching. A 200 this app cannot parse is a
    /// key that would produce an unreadable row on every poll afterwards — and
    /// it is `malformed`, not a verdict on the credential. A schema change told
    /// as "sign in again" sends somebody after a new key forever, because the
    /// new one fails in exactly the same way.
    @Test func aKeyThatFetchesButDoesNotParseIsNotBlamedForIt() async throws {
        let body = Data(#"{"usage":{"7d_used":"12"}}"#.utf8)
        let http = HostHTTP([.coding: (body, 200), .moonshot: (body, 200)])
        do {
            _ = try await KimiKeyLogin(http: http).account(for: "sk-kimi-key")
            Issue.record("an unreadable reply must not become an account")
        } catch let failure as ProviderFailure {
            #expect(failure.kind == .malformed)
        }
    }

    /// One host unreadable and the other refusing is still not a verdict on the
    /// key: the first draft folded `malformed` in with the refusals, which is
    /// the same mistake as blaming the key for a host being down.
    @Test func oneHostUnreadableAndOneRefusingBlamesNeitherOnTheKey() async throws {
        let http = HostHTTP([
            .coding: (Data(#"{"usage":{"7d_used":"12"}}"#.utf8), 200),
            .moonshot: (Data(), 401),
        ])
        do {
            _ = try await KimiKeyLogin(http: http).account(for: "sk-kimi-key")
            Issue.record("this must not produce an account")
        } catch let failure as ProviderFailure {
            #expect(failure.kind == .malformed)
        }
    }
}
