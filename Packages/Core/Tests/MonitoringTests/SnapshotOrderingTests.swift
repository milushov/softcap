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
