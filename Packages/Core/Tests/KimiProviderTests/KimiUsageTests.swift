import Testing
import Foundation
import ProviderKit
@testable import KimiProvider

/// The shape the subscription endpoint returns. Two older shapes travel beside
/// `usages` in the same reply and are deliberately not read.
private let usagesBody = Data(#"""
{"usages":{
  "limit_5h":{"used_ratio":0.086628,"reset_time":"2026-09-20T18:32:31Z"},
  "limit_7d":{"used_ratio":0.171279,"reset_time":"2026-09-22T07:32:31Z"},
  "limit_month_total":{"used_ratio":0.4,"reset_time":"2026-10-01T00:00:00Z"}}}
"""#.utf8)

private func windows(_ json: String) throws -> [LimitWindow] {
    try KimiUsageResponse.parse(Data(json.utf8)).windows
}

@Suite struct KimiUsageReading {

    @Test func bothWindowsArriveAsTheTwoThisAppAlreadyHas() throws {
        let read = try KimiUsageResponse.parse(usagesBody)
        #expect(read.windows.map(\.id) == ["session", "weekly"])
        // Computed the same way rather than written out: 0.086628 * 100 is not
        // the literal 8.6628 in binary, and a test that spells the answer
        // fails on the arithmetic rather than on the reading.
        // Hoisted and annotated, for the reason `ZaiUsageTests` carries: two
        // products in an array literal inside `#expect` are enough to put the
        // type checker over its budget on the runner.
        let expected: [Double] = [0.086628 * 100, 0.171279 * 100]
        #expect(read.windows.map(\.percent) == expected)
    }

    /// `used_ratio` is what has gone, not what is left. The other key-based
    /// service here calls its allowance `usage` and means the opposite, which
    /// is exactly why this is asserted rather than assumed.
    @Test func theRatioIsWhatHasGone() throws {
        let read = try windows(#"""
            {"usages":{"limit_5h":{"used_ratio":0.9}}}
            """#)
        #expect(read.map(\.percent) == [90])
    }

    /// An ISO instant, not the epoch milliseconds the other one sends.
    @Test func theResetIsReadAsAnInstant() throws {
        let read = try KimiUsageResponse.parse(usagesBody)
        var parts = DateComponents()
        parts.year = 2026; parts.month = 9; parts.day = 20
        parts.hour = 18; parts.minute = 32; parts.second = 31
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(read.windows.first?.resetsAt == calendar.date(from: parts))
    }

    @Test func fractionalSecondsAreReadToo() throws {
        let read = try windows(#"""
            {"usages":{"limit_5h":{"used_ratio":0.1,"reset_time":"2026-09-20T18:32:31.250Z"}}}
            """#)
        #expect(read.first?.resetsAt != nil)
    }

    @Test func aResetNobodyCanReadIsNoDeadlineRatherThanAGuess() throws {
        let read = try windows(#"""
            {"usages":{"limit_5h":{"used_ratio":0.1,"reset_time":"next tuesday"}}}
            """#)
        #expect(read.count == 1)
        #expect(read.first?.resetsAt == nil)
    }

    /// The monthly envelope is in the reply and is not drawn: a third bar in a
    /// row built for two is the cost the decision log records for Copilot.
    @Test func theMonthlyEnvelopeIsNotDrawn() throws {
        let read = try KimiUsageResponse.parse(usagesBody)
        #expect(read.windows.count == 2)
        #expect(!read.windows.contains { $0.id == "premium" })
    }

    /// One window present and one absent is one window, not a failure.
    @Test func aPlanWithOnlyOneWindowKeepsIt() throws {
        let read = try windows(#"""
            {"usages":{"limit_7d":{"used_ratio":0.5,"reset_time":"2026-09-22T07:32:31Z"}}}
            """#)
        #expect(read.map(\.id) == ["weekly"])
    }

    @Test func aRatioThatIsNotANumberSkipsItsWindow() throws {
        let read = try windows(#"""
            {"usages":{"limit_5h":{"used_ratio":"lots"},
                       "limit_7d":{"used_ratio":0.25}}}
            """#)
        #expect(read.map(\.id) == ["weekly"])
    }

    @Test func aRatioOverOneStopsAtFull() throws {
        let read = try windows(#"{"usages":{"limit_5h":{"used_ratio":1.4}}}"#)
        #expect(read.map(\.percent) == [100])
    }

    /// The older shapes are known to exist and their field names are not. A
    /// fallback written from a description could quietly produce a number, and
    /// a number this app cannot stand behind is worse than saying it could not
    /// read the reply.
    @Test func theOlderShapesAreRefusedRatherThanGuessedAt() throws {
        #expect(throws: ProviderFailure.self) {
            try windows(#"""
                {"usage":{"7d_used":"12"},"limits":[{"window":{"duration":300}}]}
                """#)
        }
    }

    @Test func aReplyWithNoWindowThisAppKnowsIsMalformed() throws {
        #expect(throws: ProviderFailure.self) {
            try windows(#"{"usages":{"limit_1y":{"used_ratio":0.1}}}"#)
        }
        #expect(throws: ProviderFailure.self) { try windows(#"{"usages":{}}"#) }
        #expect(throws: ProviderFailure.self) { try windows("[]") }
    }
}

// MARK: - the region a key belongs to

@Suite struct KimiKnowsWhichHostAKeyBelongsTo {

    @Test func theHandleCarriesTheRegionAndTheRegionComesBack() {
        for region in KimiEndpoints.Region.allCases {
            let handle = KimiEndpoints.handle(region, "abcdef0123456789")
            #expect(KimiEndpoints.region(ofHandle: handle) == region)
        }
    }

    /// A handle from before regions, or one this build cannot read, guesses at
    /// the Coding Plan's own host — a wrong guess costs a refused request, not
    /// a wrong number.
    @Test func aHandleWithoutARegionGuessesTheCodingHost() {
        #expect(KimiEndpoints.region(ofHandle: "abcdef0123456789") == .coding)
        #expect(KimiEndpoints.region(ofHandle: "mars-abcdef") == .coding)
        #expect(KimiEndpoints.region(ofHandle: "") == .coding)
    }

    @Test func theTwoHostsAreDifferentAndBothEndInUsages() {
        let addresses = KimiEndpoints.Region.allCases.map(\.usage.absoluteString)
        #expect(Set(addresses).count == KimiEndpoints.Region.allCases.count)
        #expect(addresses.allSatisfy { $0.hasSuffix("/usages") })
    }

    /// `Bearer`, unlike the other key-based service, which refuses the prefix
    /// with a 401 — two services taking a key and disagreeing about the header
    /// is obvious once and invisible afterwards.
    @Test func theKeyIsSentAsABearerToken() {
        #expect(KimiEndpoints.headers(key: "a-key")["Authorization"] == "Bearer a-key")
    }
}

// MARK: - the provider

private actor UsageHTTP: HTTPClient {
    private var replies: [(Data, Int)]
    private(set) var asked: [URL] = []
    private(set) var headers: [[String: String]] = []
    init(_ replies: [(Data, Int)]) { self.replies = replies }

    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        asked.append(url)
        self.headers.append(headers)
        return replies.isEmpty ? (Data(), 500) : replies.removeFirst()
    }

    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
        Issue.record("reading a quota must not ask a model for anything")
        return (Data(), 500)
    }
}

private actor KeptKey: AccountTokenSource {
    private(set) var handedOut = 0
    func accessToken(for account: AccountRef) async throws -> String {
        handedOut += 1
        return "sk-kimi-key"
    }
    func invalidateAccessToken(for account: AccountRef, rejectedToken: String) async {}
}

@Suite struct KimiUsage {
    private func ref(_ region: KimiEndpoints.Region = .coding) -> AccountRef {
        let handle = KimiEndpoints.handle(region, "abcdef0123456789")
        return AccountRef(
            id: "kimi/\(handle)", provider: .kimi, handle: handle, lastKnownName: "work")
    }

    @Test func aSubscriptionBecomesARowWithTwoWindows() async throws {
        let http = UsageHTTP([(usagesBody, 200)])
        let subject = KimiUsageProvider(tokens: KeptKey(), knownAccounts: [ref()], http: http)

        let snapshot = try await subject.fetch(ref())
        #expect(snapshot.failure == nil)
        #expect(snapshot.windows.map(\.id) == ["session", "weekly"])
        #expect(snapshot.displayName == "work")
        // The reply says nothing about which plan these windows belong to, and
        // a dash is what every other row without a plan shows.
        #expect(snapshot.planLabel == "—")
        #expect(await http.headers.first?["Authorization"] == "Bearer sk-kimi-key")
    }

    /// The host is decided once at sign-in and carried in the handle. Asking
    /// both every poll would be a wasted request every five minutes for
    /// everybody on the second.
    @Test(arguments: KimiEndpoints.Region.allCases)
    func theAccountIsReadFromItsOwnHost(region: KimiEndpoints.Region) async throws {
        let http = UsageHTTP([(usagesBody, 200)])
        let account = ref(region)
        let subject = KimiUsageProvider(tokens: KeptKey(), knownAccounts: [account], http: http)

        _ = try await subject.fetch(account)
        #expect(await http.asked == [region.usage])
    }

    @Test func aKeyTheStoreKeepsIsNotSentTwice() async throws {
        let tokens = KeptKey()
        let http = UsageHTTP([(Data(), 401), (usagesBody, 200)])
        let subject = KimiUsageProvider(tokens: tokens, knownAccounts: [ref()], http: http)

        #expect(try await subject.fetch(ref()).failure?.kind == .needsLogin)
        #expect(await http.asked.count == 1)
    }

    @Test func aServerFailureIsNetworkAndKeepsTheKey() async throws {
        let http = UsageHTTP([(Data(), 503)])
        let subject = KimiUsageProvider(tokens: KeptKey(), knownAccounts: [ref()], http: http)
        #expect(try await subject.fetch(ref()).failure?.kind == .network)
    }

    /// A schema this app cannot read is a visible failure, never a row of
    /// noughts.
    @Test func anUnreadableReplyIsAFailureAndNotZeroes() async throws {
        let http = UsageHTTP([(Data(#"{"usage":{"7d_used":"12"}}"#.utf8), 200)])
        let subject = KimiUsageProvider(tokens: KeptKey(), knownAccounts: [ref()], http: http)

        let snapshot = try await subject.fetch(ref())
        #expect(snapshot.failure?.kind == .malformed)
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.peakPercent == 0)
    }

    @Test func otherServicesAccountsAreNotAdopted() async throws {
        let claude = AccountRef(id: "claude/x", provider: .claude, handle: "x")
        let subject = KimiUsageProvider(
            tokens: KeptKey(), knownAccounts: [ref(), claude], http: UsageHTTP([]))
        #expect(try await subject.discoverAccounts() == [ref()])
    }
}
