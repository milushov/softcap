import Testing
import Foundation
import ProviderKit
import Preferences
@testable import Monitoring

private func make(_ id: String, peak: Double, failed: Bool = false) -> AccountSnapshot {
    AccountSnapshot(
        id: id, provider: .claude, displayName: id, planLabel: "Max",
        windows: [LimitWindow(id: "weekly", percent: peak, resetsAt: nil)],
        freshness: .live(Date(timeIntervalSince1970: 0)),
        failure: failed ? ProviderFailure(kind: .network, diagnostic: "no network") : nil
    )
}

@Test func customOrderIgnoresLoadAndFailures() {
    let rows = [make("alpha", peak: 1), make("beta", peak: 95), make("gamma", peak: 0, failed: true)]
    let ids = ["gamma", "beta", "alpha"]
    let ordered = orderedForDisplay(rows, ordering: .custom, customAccountOrder: ids)
    #expect(ordered.map(\.id) == ids)

    let refreshed = [make("beta", peak: 0, failed: true), make("gamma", peak: 99), make("alpha", peak: 50)]
    #expect(orderedForDisplay(refreshed, ordering: .custom, customAccountOrder: ids).map(\.id) == ids)
}

@Test func newAccountsFollowTheSavedOnesInNameOrder() {
    let rows = [make("zeta", peak: 10), make("beta", peak: 0), make("alpha", peak: 99)]
    let ordered = orderedForDisplay(rows, ordering: .custom, customAccountOrder: ["missing", "zeta"])
    #expect(ordered.map(\.id) == ["zeta", "alpha", "beta"])
}

@Test func duplicateSavedIDsUseTheirFirstPosition() {
    let rows = [make("alpha", peak: 0), make("beta", peak: 99)]
    let ordered = orderedForDisplay(rows, ordering: .custom, customAccountOrder: ["beta", "alpha", "beta"])
    #expect(ordered.map(\.id) == ["beta", "alpha"])
}

@Test func customOrderFallsBackToNamesBeforeAnyAccountsAreArranged() {
    let ordered = orderedForDisplay(
        [make("zeta", peak: 0), make("alpha", peak: 99, failed: true)], ordering: .custom
    )
    #expect(ordered.map(\.id) == ["alpha", "zeta"])
}

@Test func equalNamesHaveAStableFallbackOrderAcrossProviders() {
    let rows = [ProviderID.codex, .claude].map { provider in
        AccountSnapshot(
            id: "\(provider.rawValue)/example", provider: provider,
            displayName: "sam@example.com", planLabel: "",
            windows: [], freshness: .live(Date(timeIntervalSince1970: 0)), failure: nil
        )
    }
    #expect(orderedForDisplay(rows, ordering: .custom).map(\.id) == ["claude/example", "codex/example"])
    #expect(orderedForDisplay(
        rows, ordering: .custom, customAccountOrder: ["codex/example", "claude/example"]
    ).map(\.id) == ["codex/example", "claude/example"])
}

@Test func leastLoadedComesFirst() {
    let ordered = orderedForDisplay([make("c", peak: 88), make("a", peak: 5), make("b", peak: 61)])
    #expect(ordered.map(\.id) == ["a", "b", "c"])
}

@Test func failuresSinkToTheBottom() {
    let ordered = orderedForDisplay([make("bad", peak: 0, failed: true), make("busy", peak: 99)])
    #expect(ordered.map(\.id) == ["busy", "bad"])
}

@Test func tiesBreakByNameSoOrderIsStable() {
    let ordered = orderedForDisplay([make("zeta", peak: 10), make("alpha", peak: 10)])
    #expect(ordered.map(\.id) == ["alpha", "zeta"])
}

@Test func byNameIgnoresLoad() {
    let ordered = orderedForDisplay(
        [make("zeta", peak: 5), make("alpha", peak: 99)], ordering: .byName
    )
    #expect(ordered.map(\.id) == ["alpha", "zeta"])
}

@Test func byNameStillSinksFailures() {
    let ordered = orderedForDisplay(
        [make("alpha", peak: 0, failed: true), make("zeta", peak: 50)], ordering: .byName
    )
    #expect(ordered.map(\.id) == ["zeta", "alpha"])
}
