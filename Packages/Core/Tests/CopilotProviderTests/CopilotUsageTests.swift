import Testing
import Foundation
import ProviderKit
@testable import CopilotProvider

/// A paid plan: one allowance that can run out, two that cannot.
private let paidBody = Data(#"""
{"copilot_plan":"individual","quota_reset_date":"2026-10-01","quota_snapshots":{
  "premium_interactions":{"entitlement":300,"remaining":75,"percent_remaining":25,"unlimited":false,"overage_permitted":false},
  "chat":{"entitlement":0,"remaining":0,"unlimited":true},
  "completions":{"entitlement":0,"remaining":0,"unlimited":true}}}
"""#.utf8)

/// A free plan: all three are counted.
private let freeBody = Data(#"""
{"copilot_plan":"free","quota_reset_date":"2026-10-01","quota_snapshots":{
  "premium_interactions":{"entitlement":50,"remaining":10,"unlimited":false},
  "chat":{"entitlement":50,"remaining":25,"unlimited":false},
  "completions":{"entitlement":2000,"remaining":500,"unlimited":false}}}
"""#.utf8)

private let unlimitedBody = Data(#"""
{"copilot_plan":"enterprise","quota_snapshots":{
  "premium_interactions":{"unlimited":true},"chat":{"unlimited":true},"completions":{"unlimited":true}}}
"""#.utf8)

private func october() -> Date {
    var parts = DateComponents()
    parts.year = 2026
    parts.month = 10
    parts.day = 1
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: parts)!
}

private actor UsageHTTP: HTTPClient {
    private var replies: [(Data, Int)]
    private(set) var headers: [[String: String]] = []
    init(_ replies: [(Data, Int)]) { self.replies = replies }

    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        #expect(url == CopilotUsageProvider.usageURL)
        self.headers.append(headers)
        return replies.isEmpty ? (Data(), 500) : replies.removeFirst()
    }

    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
        Issue.record("reading an allowance must not ask a model for anything")
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

/// What the store does for a service that does not rotate: keeps the grant
/// rather than discarding it over one refused request.
private actor KeptTokens: AccountTokenSource {
    private(set) var handedOut = 0

    func accessToken(for account: AccountRef) async throws -> String {
        handedOut += 1
        return "gh-token"
    }

    func invalidateAccessToken(for account: AccountRef, rejectedToken: String) async {}
}

@Suite struct CopilotUsage {
    private var ref: AccountRef {
        AccountRef(id: "copilot/4711", provider: .copilot, handle: "4711", lastKnownName: "sam")
    }

    private func provider(_ replies: [(Data, Int)], tokens: UsageTokens = UsageTokens())
    -> (CopilotUsageProvider, UsageHTTP, UsageTokens) {
        let http = UsageHTTP(replies)
        return (
            CopilotUsageProvider(tokens: tokens, knownAccounts: [ref], http: http),
            http, tokens
        )
    }

    @Test func keepsOnlyTheAllowanceThatCanRunOut() async throws {
        let (subject, http, tokens) = provider([(paidBody, 200)])
        #expect(try await subject.discoverAccounts() == [ref])

        let snapshot = try await subject.fetch(ref)
        #expect(snapshot.failure == nil)
        // Two unlimited allowances are absent, not drawn at zero: a bar reading
        // nought beside something that cannot run out is the one false
        // statement this app must never make.
        #expect(snapshot.windows.map(\.id) == ["premium"])
        #expect(snapshot.windows.map(\.percent) == [75])
        #expect(snapshot.windows.first?.resetsAt == october())
        #expect(snapshot.planLabel == "Individual")
        #expect(snapshot.displayName == "sam")
        #expect(!snapshot.freshness.isStale)

        let headers = try #require(await http.headers.first)
        #expect(headers["Authorization"] == "Bearer old")
        #expect(await tokens.accounts == [ref])
    }

    /// The free plan counts all three; the row still shows the one that is
    /// drawn. The other two are left out by `kinds`, not by the plan.
    @Test func onlyThePremiumAllowanceIsDrawn() async throws {
        let (subject, _, _) = provider([(freeBody, 200)])
        let snapshot = try await subject.fetch(ref)
        #expect(snapshot.failure == nil)
        #expect(snapshot.windows.map(\.id) == ["premium"])
        #expect(snapshot.windows.map(\.percent) == [80])
        #expect(snapshot.planLabel == "Free")
        #expect(snapshot.peakPercent == 80)
    }

    /// A plan with nothing to draw is a row, not a failure.
    @Test func anUnlimitedPlanIsARowWithNoBars() async throws {
        let (subject, _, _) = provider([(unlimitedBody, 200)])
        let snapshot = try await subject.fetch(ref)
        #expect(snapshot.failure == nil)
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.planLabel == "Enterprise")
    }

    /// Which is a different sentence from a reply we could not read.
    @Test func aReplyWithoutAllowancesIsMalformed() async throws {
        let (subject, _, _) = provider([(Data(#"{"copilot_plan":"individual"}"#.utf8), 200)])
        let snapshot = try await subject.fetch(ref)
        #expect(snapshot.failure?.kind == .malformed)
        #expect(snapshot.windows.isEmpty)
    }

    @Test func notAnObjectIsMalformedToo() async throws {
        let (subject, _, _) = provider([(Data("[]".utf8), 200)])
        #expect(try await subject.fetch(ref).failure?.kind == .malformed)
    }

    @Test func retriesUnauthorizedOnceWithARefreshedToken() async throws {
        let (subject, http, tokens) = provider([(Data(), 401), (paidBody, 200)])
        let snapshot = try await subject.fetch(ref)
        #expect(snapshot.failure == nil)
        #expect(await tokens.invalidated)
        let headers = await http.headers
        #expect(headers.map { $0["Authorization"] } == ["Bearer old", "Bearer new"])
    }

    /// A retry with the same string buys a second 401 and nothing else.
    @Test func aGrantTheStoreKeepsIsNotSentTwice() async throws {
        let http = UsageHTTP([(Data(), 401), (paidBody, 200)])
        let tokens = KeptTokens()
        let subject = CopilotUsageProvider(tokens: tokens, knownAccounts: [ref], http: http)

        #expect(try await subject.fetch(ref).failure?.kind == .needsLogin)
        #expect(await http.headers.count == 1)
        // Asked for twice — once to send, once to see whether anything replaced
        // it — and sent once.
        #expect(await tokens.handedOut == 2)
    }

    @Test func aSecondRefusalAsksForASignIn() async throws {
        let (subject, _, _) = provider([(Data(), 401), (Data(), 401)])
        #expect(try await subject.fetch(ref).failure?.kind == .needsLogin)
    }

    @Test func aServerFailureIsNetworkAndKeepsTheGrant() async throws {
        let (subject, _, _) = provider([(Data(), 503)])
        #expect(try await subject.fetch(ref).failure?.kind == .network)
    }

    @Test func anAccountThisProviderDoesNotHoldIsRefused() async throws {
        let (subject, _, _) = provider([(paidBody, 200)])
        let stranger = AccountRef(id: "copilot/other", provider: .copilot, handle: "other")
        #expect(try await subject.fetch(stranger).failure?.kind == .needsLogin)
    }

    @Test func otherServicesAccountsAreNotAdopted() async throws {
        let http = UsageHTTP([])
        let claude = AccountRef(id: "claude/x", provider: .claude, handle: "x")
        let subject = CopilotUsageProvider(
            tokens: UsageTokens(), knownAccounts: [ref, claude], http: http)
        #expect(try await subject.discoverAccounts() == [ref])
    }
}

@Suite struct CopilotQuotaReading {
    private func windows(_ json: String) throws -> [LimitWindow] {
        try CopilotQuotaResponse.parse(Data(json.utf8)).windows
    }

    /// The exact pair is divided rather than the rounded percentage read.
    @Test func percentIsCountedFromTheTwoCounts() throws {
        let read = try windows(#"""
            {"quota_snapshots":{"premium_interactions":
              {"entitlement":300,"remaining":75,"percent_remaining":99,"unlimited":false}}}
            """#)
        #expect(read.map(\.percent) == [75])
    }

    @Test func theReportedPercentServesWhenTheCountsDoNot() throws {
        let read = try windows(#"""
            {"quota_snapshots":{"premium_interactions":{"percent_remaining":40,"unlimited":false}}}
            """#)
        #expect(read.map(\.percent) == [60])
    }

    @Test func aFloatingRemainderIsRead() throws {
        let read = try windows(#"""
            {"quota_snapshots":{"premium_interactions":
              {"entitlement":200,"quota_remaining":50.5,"unlimited":false}}}
            """#)
        #expect(read.map(\.percent) == [74.75])
    }

    /// Overage runs a count past its entitlement; a bar still ends at its end.
    @Test func goingOverStopsAtFull() throws {
        let read = try windows(#"""
            {"quota_snapshots":{"premium_interactions":
              {"entitlement":100,"remaining":-20,"unlimited":false,"overage_permitted":true}}}
            """#)
        #expect(read.map(\.percent) == [100])
    }

    @Test func anAllowanceThisPlanDoesNotHaveIsLeftOut() throws {
        let read = try windows(#"""
            {"quota_snapshots":{"premium_interactions":{"entitlement":0,"remaining":0,"unlimited":false}}}
            """#)
        #expect(read.isEmpty)
    }

    @Test func anAllowanceTheServiceSaysIsNotOneIsLeftOut() throws {
        let read = try windows(#"""
            {"quota_snapshots":{"premium_interactions":
              {"has_quota":false,"entitlement":10,"remaining":1,"unlimited":false}}}
            """#)
        #expect(read.isEmpty)
    }

    /// The two the row does not draw are not read at all, whatever they say.
    @Test func theOtherTwoAllowancesAreNotWindows() throws {
        let read = try windows(#"""
            {"quota_snapshots":{"chat":{"entitlement":50,"remaining":25,"unlimited":false},
                                "completions":{"entitlement":2000,"remaining":500,"unlimited":false}}}
            """#)
        #expect(read.isEmpty)
    }

    @Test func theSkuNamesThePlanWhenThePlanDoesNot() throws {
        let read = try CopilotQuotaResponse.parse(Data(#"""
            {"access_type_sku":"copilot_pro_plus","quota_snapshots":{}}
            """#.utf8))
        #expect(read.planLabel == "Copilot Pro Plus")
    }

    @Test func anUnnamedPlanIsADash() throws {
        let read = try CopilotQuotaResponse.parse(Data(#"{"quota_snapshots":{}}"#.utf8))
        #expect(read.planLabel == "—")
    }

    @Test func aResetDateOnTheAllowanceBeatsTheOneBesideIt() throws {
        let read = try windows(#"""
            {"quota_reset_date":"2026-10-01","quota_snapshots":{"premium_interactions":
              {"entitlement":10,"remaining":5,"unlimited":false,"quota_reset_date":"2026-11-01"}}}
            """#)
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 11
        parts.day = 1
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(read.first?.resetsAt == calendar.date(from: parts))
    }

    @Test func noResetDateIsNoDeadlineRatherThanAGuess() throws {
        let read = try windows(#"""
            {"quota_snapshots":{"premium_interactions":{"entitlement":10,"remaining":5,"unlimited":false}}}
            """#)
        #expect(read.first?.resetsAt == nil)
    }
}
