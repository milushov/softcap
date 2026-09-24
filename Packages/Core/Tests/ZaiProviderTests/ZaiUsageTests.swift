import Testing
import Foundation
import ProviderKit
@testable import ZaiProvider

/// The shape the service returns today.
private let currentBody = Data(#"""
{"code":200,"msg":"Operation successful","success":true,"data":{"level":"lite","limits":[
  {"type":"CREDIT_LIMIT","unit":3,"number":5,"usage":2000,"currentValue":251,
   "remaining":1748,"percentage":12,"nextResetTime":1790256683169},
  {"type":"CREDIT_LIMIT","unit":6,"number":1,"usage":10000,"currentValue":251,
   "remaining":9748,"percentage":2,"nextResetTime":1790791834975}]}}
"""#.utf8)

/// The shape it returned until recently. Same pairs, different `type`.
private let legacyBody = Data(#"""
{"code":200,"success":true,"data":{"level":"pro","limits":[
  {"type":"TOKENS_LIMIT","unit":3,"number":5,"usage":2000,"currentValue":500,
   "nextResetTime":1790256683169},
  {"type":"TIME_LIMIT","unit":5,"number":1,"usage":300,"currentValue":30,
   "nextResetTime":1790791834975}]}}
"""#.utf8)

private func windows(_ json: String) throws -> [LimitWindow] {
    try ZaiQuotaResponse.parse(Data(json.utf8)).windows
}

@Suite struct ZaiQuotaReading {

    @Test func bothWindowsArriveAsTheTwoThisAppAlreadyHas() throws {
        let read = try ZaiQuotaResponse.parse(currentBody)
        // `session` and `weekly`: nothing new is named, so no catalogue gains a
        // key and the period column keeps the width it has.
        #expect(read.windows.map(\.id) == ["session", "weekly"])
        #expect(read.windows.map(\.percent) == [251.0 / 2000 * 100, 251.0 / 10000 * 100])
        #expect(read.planLabel == "Lite")
    }

    /// The trap the field names set.
    ///
    /// `usage` is the allowance and `currentValue` is what has gone. Reading
    /// them the obvious way gives 2000/251 — a number that is plausible, wrong,
    /// and wrong in the reassuring direction.
    @Test func theAllowanceIsUsageAndTheSpendIsCurrentValue() throws {
        let read = try windows(#"""
            {"success":true,"data":{"limits":[
              {"unit":3,"number":5,"usage":1000,"currentValue":900}]}}
            """#)
        #expect(read.map(\.percent) == [90])
    }

    /// `type` changed under every reader that keyed on it. This one does not.
    @Test func theOldTypeNamesStillParse() throws {
        let read = try ZaiQuotaResponse.parse(legacyBody)
        #expect(read.windows.map(\.id) == ["session"])
        #expect(read.windows.map(\.percent) == [25])
        #expect(read.planLabel == "Pro")
    }

    /// The legacy monthly MCP allowance is not one of this app's two windows
    /// and is not turned into one.
    @Test func aPairThisAppDoesNotKnowIsLeftOut() throws {
        let read = try windows(#"""
            {"success":true,"data":{"limits":[
              {"unit":3,"number":5,"usage":100,"currentValue":10},
              {"unit":5,"number":1,"usage":300,"currentValue":30},
              {"unit":9,"number":9,"usage":10,"currentValue":1}]}}
            """#)
        #expect(read.map(\.id) == ["session"])
    }

    /// Keying on the unit alone would file a one-hour window as `session`,
    /// which is labelled `5h` in ten catalogues — a wrong period stated
    /// confidently beside a right number.
    @Test func anHourWindowIsNotTheFiveHourWindow() throws {
        let read = try windows(#"""
            {"success":true,"data":{"limits":[
              {"unit":3,"number":1,"usage":100,"currentValue":80},
              {"unit":3,"number":5,"usage":100,"currentValue":10}]}}
            """#)
        #expect(read.map(\.id) == ["session"])
        #expect(read.map(\.percent) == [10], "the five-hour window is the one drawn, not the hour")
    }

    /// And on its own it is not a window at all.
    @Test func anHourWindowAloneIsMalformed() throws {
        #expect(throws: ProviderFailure.self) {
            try windows(#"""
                {"success":true,"data":{"limits":[{"unit":3,"number":1,"usage":100,"currentValue":80}]}}
                """#)
        }
    }

    @Test func aReplyWithNoWindowThisAppKnowsIsMalformed() throws {
        #expect(throws: ProviderFailure.self) {
            try windows(#"""
                {"success":true,"data":{"limits":[{"unit":9,"number":9,"usage":10,"currentValue":1}]}}
                """#)
        }
    }

    /// The service is changing what its entries look like. One of a shape this
    /// app has not met must not take the real windows down with it.
    @Test func anEntryThisAppCannotReadCostsOnlyItself() throws {
        let read = try windows(#"""
            {"success":true,"data":{"limits":[
              "a string where an object was",
              {"unit":3,"number":5,"usage":100,"currentValue":40},
              {"unit":6,"number":1,"usage":100,"currentValue":10}]}}
            """#)
        #expect(read.map(\.id) == ["session", "weekly"])
        #expect(read.map(\.percent) == [40, 10])
    }

    @Test func anEmptyLimitsArrayIsMalformedRatherThanAnEmptyRow() throws {
        #expect(throws: ProviderFailure.self) {
            try windows(#"{"success":true,"data":{"limits":[]}}"#)
        }
    }

    /// A revoked key arrives as a 200 with the reason in `code`. It has to be
    /// `needsLogin`: every screen gates the offer to sign in again on that one
    /// kind, so `malformed` would put "the reply could not be read" on the only
    /// failure a person can actually do something about.
    @Test(arguments: [401, 403])
    func aRefusedKeyInsideATwoHundredAsksForANewOne(code: Int) throws {
        do {
            _ = try windows("""
                {"code":\(code),"msg":"invalid token","success":false,"data":null}
                """)
            Issue.record("success:false must not parse to a row")
        } catch let failure as ProviderFailure {
            #expect(failure.kind == .needsLogin)
            #expect(failure.diagnostic.contains("invalid token"))
        }
    }

    /// The same refusal with its fields as strings. This service is changing
    /// its schema, and a revoked key must stay a revoked key through that —
    /// `malformed` would take the way back in off every screen.
    @Test func aRefusalSpeltWithStringsIsStillARefusedKey() throws {
        do {
            _ = try windows(#"{"code":"401","msg":"invalid token","success":"false"}"#)
            Issue.record("a refusal spelt with strings must not parse to a row")
        } catch let failure as ProviderFailure {
            #expect(failure.kind == .needsLogin)
        }
    }

    /// A share far too large is full, not empty.
    ///
    /// The direction matters more than the number. Clamping used to send
    /// anything it could not make sense of to nought, and nought is the one
    /// reading this app must never invent — a window at a hundred is at worst
    /// alarming, a window at zero is a lie that reassures.
    @Test func anAbsurdShareIsFullRatherThanEmpty() throws {
        let read = try windows(#"""
            {"success":true,"data":{"limits":[
              {"unit":3,"number":5,"percentage":1e308},
              {"unit":6,"number":1,"usage":100,"currentValue":25}]}}
            """#)
        #expect(read.map(\.id) == ["session", "weekly"])
        #expect(read.map(\.percent) == [100, 25])
    }

    /// The diagnostic names what the service sent, not what survived reading
    /// it: "held 0 limits" would point at an empty array rather than at the
    /// schema change that is the actual cause.
    @Test func theDiagnosticCountsWhatArrived() throws {
        do {
            _ = try windows(#"""
                {"success":true,"data":{"limits":["one","two","three"]}}
                """#)
            Issue.record("three unreadable entries must not parse to a row")
        } catch let failure as ProviderFailure {
            #expect(failure.diagnostic.contains("3 limits"))
        }
    }

    /// Any other refusal is still a reply this app could not turn into windows.
    @Test func anotherRefusalInsideATwoHundredIsMalformed() throws {
        do {
            _ = try windows(#"{"code":500,"msg":"upstream unavailable","success":false}"#)
            Issue.record("success:false must not parse to a row")
        } catch let failure as ProviderFailure {
            #expect(failure.kind == .malformed)
            #expect(failure.diagnostic.contains("upstream unavailable"))
        }
    }

    /// An allowance the service states as zero is a window this plan does not
    /// have. Drawing it at nought would be the row of noughts by another road.
    @Test func awindowWithNoAllowanceIsNotAWindowAtNought() throws {
        let read = try windows(#"""
            {"success":true,"data":{"limits":[
              {"unit":3,"number":5,"usage":0,"currentValue":0,"percentage":0},
              {"unit":6,"number":1,"usage":100,"currentValue":25}]}}
            """#)
        #expect(read.map(\.id) == ["weekly"])
        #expect(read.map(\.percent) == [25])
    }

    @Test func aPlanWhoseWindowsAllStateNoAllowanceIsMalformed() throws {
        #expect(throws: ProviderFailure.self) {
            try windows(#"""
                {"success":true,"data":{"limits":[
                  {"unit":3,"number":5,"usage":0,"currentValue":0,"percentage":0}]}}
                """#)
        }
    }

    @Test func aReplyWithoutLimitsIsMalformed() throws {
        #expect(throws: ProviderFailure.self) { try windows(#"{"success":true,"data":{}}"#) }
        #expect(throws: ProviderFailure.self) { try windows(#"{"success":true}"#) }
        #expect(throws: ProviderFailure.self) { try windows("[]") }
    }

    /// Milliseconds. Read as seconds the reset lands fifty thousand years out.
    @Test func theResetIsReadAsMilliseconds() throws {
        let read = try ZaiQuotaResponse.parse(currentBody)
        #expect(read.windows.first?.resetsAt == Date(timeIntervalSince1970: 1_790_256_683.169))
        #expect(read.windows.last?.resetsAt == Date(timeIntervalSince1970: 1_790_791_834.975))
    }

    @Test func noResetTimeIsNoDeadlineRatherThanAGuess() throws {
        let read = try windows(#"""
            {"success":true,"data":{"limits":[{"unit":3,"number":5,"usage":100,"currentValue":10}]}}
            """#)
        #expect(read.first?.resetsAt == nil)
    }

    @Test func theReportedPercentServesWhenTheCountsDoNot() throws {
        let read = try windows(#"""
            {"success":true,"data":{"limits":[{"unit":3,"number":5,"percentage":42}]}}
            """#)
        #expect(read.map(\.percent) == [42])
    }

    @Test func goingOverStopsAtFull() throws {
        let read = try windows(#"""
            {"success":true,"data":{"limits":[{"unit":3,"number":5,"usage":100,"currentValue":140}]}}
            """#)
        #expect(read.map(\.percent) == [100])
    }

    /// Which of two identical windows is drawn must not depend on the order the
    /// service happened to serialise them in.
    @Test func aRepeatedWindowTakesTheFirst() throws {
        let read = try windows(#"""
            {"success":true,"data":{"limits":[
              {"unit":3,"number":5,"usage":100,"currentValue":10},
              {"unit":3,"number":5,"usage":100,"currentValue":90}]}}
            """#)
        #expect(read.map(\.percent) == [10])
    }

    @Test func anUnnamedPlanIsADash() throws {
        let read = try ZaiQuotaResponse.parse(Data(#"""
            {"success":true,"data":{"limits":[{"unit":3,"number":5,"usage":10,"currentValue":1}]}}
            """#.utf8))
        #expect(read.planLabel == "—")
    }
}

// MARK: - the provider

private actor UsageHTTP: HTTPClient {
    private var replies: [(Data, Int)]
    private(set) var headers: [[String: String]] = []
    init(_ replies: [(Data, Int)]) { self.replies = replies }

    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        #expect(url == ZaiUsageProvider.usageURL)
        self.headers.append(headers)
        return replies.isEmpty ? (Data(), 500) : replies.removeFirst()
    }

    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
        Issue.record("reading a quota must not ask a model for anything")
        return (Data(), 500)
    }
}

/// What the store does for a service that does not rotate: keeps the key.
private actor KeptKey: AccountTokenSource {
    private(set) var handedOut = 0
    func accessToken(for account: AccountRef) async throws -> String {
        handedOut += 1
        return "zai-key"
    }
    func invalidateAccessToken(for account: AccountRef, rejectedToken: String) async {}
}

/// And what it would do if one ever did.
private actor RotatingKey: AccountTokenSource {
    private var invalidated = false
    func accessToken(for account: AccountRef) async throws -> String {
        invalidated ? "new" : "old"
    }
    func invalidateAccessToken(for account: AccountRef, rejectedToken: String) async {
        invalidated = true
    }
}

@Suite struct ZaiUsage {
    private var ref: AccountRef {
        AccountRef(id: "glm/1", provider: .glm, handle: "1", lastKnownName: "work plan")
    }

    private func provider(
        _ replies: [(Data, Int)], tokens: any AccountTokenSource = KeptKey()
    ) -> (ZaiUsageProvider, UsageHTTP) {
        let http = UsageHTTP(replies)
        return (ZaiUsageProvider(tokens: tokens, knownAccounts: [ref], http: http), http)
    }

    @Test func aPlanBecomesARowWithTwoWindows() async throws {
        let (subject, http) = provider([(currentBody, 200)])
        #expect(try await subject.discoverAccounts() == [ref])

        let snapshot = try await subject.fetch(ref)
        #expect(snapshot.failure == nil)
        #expect(snapshot.windows.map(\.id) == ["session", "weekly"])
        #expect(snapshot.planLabel == "Lite")
        #expect(snapshot.displayName == "work plan")
        #expect(!snapshot.freshness.isStale)

        let headers = try #require(await http.headers.first)
        // Bare. The prefix every other service requires is refused here with a
        // 401, which reads as a dead key rather than as a wrong header.
        #expect(headers["Authorization"] == "zai-key")
        #expect(headers["Authorization"]?.hasPrefix("Bearer") == false)
    }

    @Test func aKeyTheStoreKeepsIsNotSentTwice() async throws {
        let tokens = KeptKey()
        let (subject, http) = provider([(Data(), 401), (currentBody, 200)], tokens: tokens)
        #expect(try await subject.fetch(ref).failure?.kind == .needsLogin)
        #expect(await http.headers.count == 1)
        #expect(await tokens.handedOut == 2)
    }

    @Test func aReplacedCredentialIsRetriedOnce() async throws {
        let (subject, http) = provider([(Data(), 401), (currentBody, 200)], tokens: RotatingKey())
        #expect(try await subject.fetch(ref).failure == nil)
        #expect(await http.headers.map { $0["Authorization"] } == ["old", "new"])
    }

    @Test func aServerFailureIsNetworkAndKeepsTheKey() async throws {
        let (subject, _) = provider([(Data(), 503)])
        #expect(try await subject.fetch(ref).failure?.kind == .network)
    }

    @Test func aRefusedKeyAsksForANewOne() async throws {
        let (subject, _) = provider([(Data(), 403)])
        #expect(try await subject.fetch(ref).failure?.kind == .needsLogin)
    }

    /// A schema this app cannot read becomes a visible failure, never a row of
    /// noughts. Several other readers turned exactly this into zeros.
    @Test func anUnreadableSchemaIsAFailureAndNotZeroes() async throws {
        let (subject, _) = provider([(Data(#"""
            {"success":true,"data":{"limits":[{"type":"SOMETHING_NEW","unit":11,"number":3}]}}
            """#.utf8), 200)])
        let snapshot = try await subject.fetch(ref)
        #expect(snapshot.failure?.kind == .malformed)
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.peakPercent == 0)
    }

    @Test func anAccountThisProviderDoesNotHoldIsRefused() async throws {
        let (subject, _) = provider([(currentBody, 200)])
        let stranger = AccountRef(id: "glm/other", provider: .glm, handle: "other")
        #expect(try await subject.fetch(stranger).failure?.kind == .needsLogin)
    }

    @Test func otherServicesAccountsAreNotAdopted() async throws {
        let http = UsageHTTP([])
        let claude = AccountRef(id: "claude/x", provider: .claude, handle: "x")
        let subject = ZaiUsageProvider(
            tokens: KeptKey(), knownAccounts: [ref, claude], http: http)
        #expect(try await subject.discoverAccounts() == [ref])
    }
}
