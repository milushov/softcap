import Testing
import Foundation
import ProviderKit
import Preferences
@testable import Monitoring

private struct FakeProvider: UsageProvider {
    let id: ProviderID
    let refs: [AccountRef]
    let snapshots: [String: AccountSnapshot]
    var failDiscovery = false

    func discoverAccounts() async throws -> [AccountRef] {
        if failDiscovery { throw ProviderFailure(kind: .network, diagnostic: "no network") }
        return refs
    }

    func fetch(_ ref: AccountRef) async throws -> AccountSnapshot {
        guard let snapshot = snapshots[ref.id] else {
            throw ProviderFailure(kind: .noData, diagnostic: "no data")
        }
        return snapshot
    }
}

private func snap(
    _ id: String, provider: ProviderID = .claude, peak: Double, resetsIn: TimeInterval? = nil
) -> AccountSnapshot {
    AccountSnapshot(
        id: id, provider: provider, displayName: id, planLabel: "Max",
        windows: [LimitWindow(id: "weekly", percent: peak,
            resetsAt: resetsIn.map { Date(timeIntervalSince1970: 1_000_000 + $0) }
        )],
        freshness: .live(Date(timeIntervalSince1970: 1_000_000)), failure: nil
    )
}

private func makeProvider(_ items: [AccountSnapshot], id: ProviderID = .claude) -> FakeProvider {
    FakeProvider(
        id: id,
        refs: items.map { AccountRef(id: $0.id, provider: id, handle: $0.id) },
        snapshots: Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    )
}

@Test func gathersFromEveryProviderInDisplayOrder() async {
    let poller = UsagePoller(providers: [
        makeProvider([snap("busy", peak: 88), snap("free", peak: 4)]),
        makeProvider([snap("codex", provider: .codex, peak: 32)], id: .codex),
    ])
    let result = await poller.refresh()
    #expect(result.map(\.id) == ["free", "codex", "busy"])
}

/// The name of this test is the point of it, and it still holds: a provider that
/// cannot be asked must not take the others down with it. What changed is what
/// happens to the broken one — it used to be skipped, which is a quieter failure
/// than it deserves. It gets a row of its own now.
@Test func oneBrokenProviderDoesNotHideTheOthers() async {
    var broken = makeProvider([], id: .codex)
    broken.failDiscovery = true

    let poller = UsagePoller(providers: [makeProvider([snap("ok", peak: 10)]), broken])
    let result = await poller.refresh()

    #expect(result.contains { $0.id == "ok" && $0.failure == nil },
            "the working provider's account was lost")
    #expect(result.contains { $0.provider == .codex && $0.failure != nil },
            "the broken provider vanished instead of reporting")
    #expect(result.count == 2, "got \(result.map(\.id))")
}

@Test func failedFetchBecomesVisibleRowNotSilence() async {
    let provider = FakeProvider(
        id: .claude,
        refs: [AccountRef(id: "gone", provider: .claude, handle: "gone")],
        snapshots: [:]
    )
    let result = await UsagePoller(providers: [provider]).refresh()
    #expect(result.count == 1)
    #expect(result[0].failure?.kind == .noData)
    #expect(result[0].id == "gone")
}

@Test func cacheSurvivesUntilNextRefresh() async {
    let poller = UsagePoller(providers: [makeProvider([snap("a", peak: 10)])])
    #expect(await poller.cached().isEmpty)
    _ = await poller.refresh()
    #expect(await poller.cached().map(\.id) == ["a"])
}

@Test func menuBarShowsTheWindowClosestToExhaustion() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let summary = menuBarSummary([
        snap("free", peak: 5, resetsIn: 60),        // resets sooner, but it is not the one that matters
        snap("busy", peak: 92, resetsIn: 2_820),    // 47 minutes
    ], now: now)

    #expect(summary?.percent == 92)
    #expect(summary?.severity == .critical)
    #expect(summary?.remaining == 2_820)
}

@Test func menuBarIsEmptyWithoutAccounts() {
    #expect(menuBarSummary([], now: Date()) == nil)
}

@Test func menuBarCanBePinnedToWeeklyWindow() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let account = AccountSnapshot(
        id: "a", provider: .claude, displayName: "a", planLabel: "Max",
        windows: [
            LimitWindow(id: "session", percent: 90, resetsAt: nil),
            LimitWindow(id: "weekly", percent: 20, resetsAt: nil),
        ],
        freshness: .live(now), failure: nil
    )
    #expect(menuBarSummary([account], now: now, window: .worst)?.percent == 90)
    #expect(menuBarSummary([account], now: now, window: .weekly)?.percent == 20)
    #expect(menuBarSummary([account], now: now, window: .session)?.percent == 90)
}

@Test func pollerWithoutProvidersReturnsNothing() async {
    let result = await UsagePoller(providers: []).refresh()
    #expect(result.isEmpty)
}

/// A row built because the provider threw is the row a person reads when
/// something is wrong, so it is the one that most needs to say which account it
/// is about. It showed the identifier — `claude/` and a UUID — which is the one
/// thing about the account nobody has ever seen.
///
/// The provider has its own fallback, and it is not reached when the provider
/// throws before returning anything. This row is built by the poller.
@Suite struct NamingAnAccountThePollerCouldNotRead {

    private struct AlwaysThrows: UsageProvider {
        let id: ProviderID = .claude
        let refs: [AccountRef]
        func discoverAccounts() async throws -> [AccountRef] { refs }
        func fetch(_ ref: AccountRef) async throws -> AccountSnapshot {
            throw ProviderFailure(kind: .needsLogin, diagnostic: "no token")
        }
    }

    @Test func theFailedRowKeepsTheNameTheAccountWasKnownBy() async {
        let ref = AccountRef(id: "claude/u-1", provider: .claude, handle: "u-1",
                             lastKnownName: "sam@example.com")
        let poller = UsagePoller(providers: [AlwaysThrows(refs: [ref])])
        let result = await poller.refresh()
        #expect(result.count == 1)
        #expect(result.first?.displayName == "sam@example.com")
        #expect(result.first?.failure != nil)
    }

    @Test func theIdentifierRemainsTheLastResort() async {
        let ref = AccountRef(id: "claude/u-1", provider: .claude, handle: "u-1")
        let poller = UsagePoller(providers: [AlwaysThrows(refs: [ref])])
        let result = await poller.refresh()
        #expect(result.first?.displayName == "claude/u-1")
    }
}

/// A provider that cannot list its accounts used to be skipped, and so vanished
/// from the window with nothing to say why.
@Suite struct AProviderThatCannotBeAsked {

    private struct Unlistable: UsageProvider {
        let id: ProviderID = .codex
        func discoverAccounts() async throws -> [AccountRef] {
            throw ProviderFailure(kind: .malformed, diagnostic: "id_token not parsed")
        }
        func fetch(_ ref: AccountRef) async throws -> AccountSnapshot {
            Issue.record("fetch was reached without any accounts")
            throw ProviderFailure(kind: .noData, diagnostic: "unreachable")
        }
    }

    @Test func itGetsARowNamingTheService() async {
        let poller = UsagePoller(providers: [Unlistable()])
        let result = await poller.refresh()
        #expect(result.count == 1, "the provider vanished instead of reporting")
        #expect(result.first?.displayName == ProviderID.codex.title)
        #expect(result.first?.failure?.kind == .malformed)
    }
}
