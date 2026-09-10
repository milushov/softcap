import Testing
import Foundation
import ProviderKit
@testable import CodexProvider

private let usageBody = Data(#"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":25,"reset_at":1800000000},"secondary_window":{"used_percent":70,"reset_after_seconds":120}}}"#.utf8)

private actor UsageHTTP: HTTPClient {
    private var replies: [(Data, Int)]
    private(set) var headers: [[String: String]] = []
    init(_ replies: [(Data, Int)]) { self.replies = replies }
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        #expect(url == CodexLiveUsageProvider.usageURL)
        self.headers.append(headers)
        return replies.isEmpty ? (Data(), 500) : replies.removeFirst()
    }
    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
        Issue.record("reading usage must not make an inference request")
        return (Data(), 500)
    }
}

private actor UsageTokens: AccountTokenSource {
    private(set) var invalidated = false
    private(set) var accounts: [AccountRef] = []
    func accessToken(for account: AccountRef) async throws -> String {
        accounts.append(account)
        return invalidated ? "new" : "old"
    }
    func invalidateAccessToken(for account: AccountRef, rejectedToken: String) async {
        #expect(rejectedToken == "old")
        invalidated = true
    }
}

@Suite struct CodexLiveUsage {
    private var ref: AccountRef {
        AccountRef(id: "codex/saved", provider: .codex, handle: "saved", lastKnownName: "sam@example.com")
    }

    @Test func readsLiveUsageWithoutAnyLocalFiles() async throws {
        let http = UsageHTTP([(usageBody, 200)])
        let tokens = UsageTokens()
        let provider = CodexLiveUsageProvider(tokens: tokens, knownAccounts: [ref], http: http)
        #expect(try await provider.discoverAccounts() == [ref])
        let snapshot = try await provider.fetch(ref)
        #expect(snapshot.failure == nil)
        #expect(snapshot.windows.map(\.percent) == [25, 70])
        #expect(snapshot.planLabel == "Plus")
        #expect(!snapshot.freshness.isStale)
        #expect(snapshot.displayName == "sam@example.com")
        let headers = try #require(await http.headers.first)
        #expect(headers["ChatGPT-Account-Id"] == "saved")
        #expect(headers["Authorization"] == "Bearer old")
        #expect(headers["anthropic-beta"] == nil)
        #expect(await tokens.accounts == [ref])
    }

    @Test func retriesUnauthorizedOnceWithRefreshedAccess() async throws {
        let http = UsageHTTP([(Data(), 401), (usageBody, 200)])
        let tokens = UsageTokens()
        let result = try await CodexLiveUsageProvider(tokens: tokens, knownAccounts: [ref], http: http).fetch(ref)
        #expect(result.failure == nil)
        #expect(await http.headers.map { $0["Authorization"] } == ["Bearer old", "Bearer new"])
    }

    @Test func stopsRetryingAndPreservesAccountName() async throws {
        let http = UsageHTTP([(Data(), 401), (Data(), 401)])
        let result = try await CodexLiveUsageProvider(tokens: UsageTokens(), knownAccounts: [ref], http: http).fetch(ref)
        #expect(result.failure?.kind == .needsLogin)
        #expect(result.displayName == "sam@example.com")
        #expect(await http.headers.count == 2)
    }

    @Test func temporaryFailureDoesNotAskForLogin() async throws {
        let http = UsageHTTP([(Data(), 429)])
        let result = try await CodexLiveUsageProvider(tokens: UsageTokens(), knownAccounts: [ref], http: http).fetch(ref)
        #expect(result.failure?.kind == .network)
        #expect(await http.headers.count == 1)
    }

    @Test func namespaceFiltersClaudeAccounts() async throws {
        let claude = AccountRef(id: "claude/saved", provider: .claude, handle: "saved")
        let provider = CodexLiveUsageProvider(tokens: UsageTokens(), knownAccounts: [ref, claude])
        #expect(try await provider.discoverAccounts() == [ref])
    }

    @Test func parsesBothResetFormatsWithoutTreatingMissingDataAsZero() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let result = try CodexUsageResponse.parse(usageBody, now: now)
        #expect(result.windows[0].resetsAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(result.windows[1].resetsAt == now.addingTimeInterval(120))
        for invalid in [#"{}"#, #"{"rate_limit":{}}"#,
                        #"{"rate_limit":{"primary_window":{"used_percent":101}}}"#,
                        #"{"rate_limit":{"primary_window":{"used_percent":true}}}"#,
                        #"{"rate_limit":{"primary_window":{}}}"#] {
            #expect(throws: ProviderFailure.self) { try CodexUsageResponse.parse(Data(invalid.utf8)) }
        }
    }

    @Test func aWeeklyPrimaryWindowIsLabelledByDuration() throws {
        let body = Data(#"{"rate_limit":{"primary_window":{"used_percent":45,"limit_window_seconds":604800},"secondary_window":null}}"#.utf8)
        #expect(try CodexUsageResponse.parse(body).windows.map(\.id) == ["weekly"])
    }
}
