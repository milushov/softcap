import Testing
import Foundation
@testable import Monitoring
import ProviderKit

/// What the menu bar shows all day, and nothing was checking it.
///
/// `menuBarSummary` decides the one number and the one countdown a person sees
/// without opening anything. It is a free function with three modes and a
/// deliberate choice inside it, and no test mentioned it.
@Suite struct TheMenuBarSummary {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func account(
        _ id: String, session: (Double, TimeInterval)? = nil, weekly: (Double, TimeInterval)? = nil,
        failed: Bool = false
    ) -> AccountSnapshot {
        var windows: [LimitWindow] = []
        if let session {
            windows.append(LimitWindow(id: "session", percent: session.0,
                                       resetsAt: now.addingTimeInterval(session.1)))
        }
        if let weekly {
            windows.append(LimitWindow(id: "weekly", percent: weekly.0,
                                       resetsAt: now.addingTimeInterval(weekly.1)))
        }
        return AccountSnapshot(
            id: id, provider: .claude, displayName: id, planLabel: "Max 20x",
            windows: windows, freshness: .live(now),
            failure: failed ? ProviderFailure(kind: .needsLogin, diagnostic: "") : nil
        )
    }

    /// The busiest window across every account, not the soonest to reset. A free
    /// account's reset is the soonest and says nothing about where to work.
    @Test func itTakesTheBusiestWindowNotTheNearestReset() {
        let snapshots = [
            account("idle", session: (2, 600)),      // resets in ten minutes
            account("busy", session: (91, 7200)),    // resets in two hours
        ]
        let summary = menuBarSummary(snapshots, now: now)
        #expect(summary?.percent == 91)
        #expect(summary?.remaining == 7200, "the countdown belongs to the window it chose")
    }

    /// Each account contributes its own worst window, then the worst of those
    /// wins — so a quiet account with one hot window still surfaces.
    @Test func eachAccountOffersItsOwnPeak() {
        let snapshots = [
            account("a", session: (10, 3600), weekly: (40, 86400)),
            account("b", session: (70, 1800), weekly: (5, 86400)),
        ]
        #expect(menuBarSummary(snapshots, now: now)?.percent == 70)
    }

    @Test func askingForOneWindowIgnoresTheOther() {
        let snapshots = [
            account("a", session: (95, 600), weekly: (20, 86400)),
            account("b", session: (10, 600), weekly: (60, 86400)),
        ]
        #expect(menuBarSummary(snapshots, now: now, window: .session)?.percent == 95)
        #expect(menuBarSummary(snapshots, now: now, window: .weekly)?.percent == 60)
    }

    /// A failed account carries no windows. It must not blank the strip for the
    /// accounts that are answering — which is the state this machine is in.
    @Test func anAccountThatFailedDoesNotSilenceTheRest() {
        let snapshots = [
            account("broken", failed: true),
            account("working", weekly: (55, 3600)),
        ]
        let summary = menuBarSummary(snapshots, now: now)
        #expect(summary?.percent == 55)
    }

    @Test func nothingToShowIsNothing() {
        #expect(menuBarSummary([], now: now) == nil)
        #expect(menuBarSummary([account("broken", failed: true)], now: now) == nil)
    }

    /// The colour comes from the window that was chosen, so the strip and the
    /// row agree about how bad it is.
    @Test func theSeverityIsTheChosenWindows() {
        let summary = menuBarSummary([account("a", weekly: (96, 600))], now: now)
        #expect(summary?.severity == Severity(percent: 96))
    }
}
