import Testing
import Foundation
import ProviderKit
import Preferences
@testable import Monitoring

/// The menu bar says something about every account there is.
///
/// "Primary window" offers the five-hour or the weekly, and the summary used to
/// take that literally: it filtered every account's windows for that identifier
/// and dropped whatever did not match. While the two services both reported
/// both windows, nothing could fail to match. A service reporting one monthly
/// allowance matches neither — so a person whose only accounts were of that
/// kind got no label at all, above a window that was drawing their limits
/// perfectly well.
///
/// The row already knew better: `AccountSnapshot.headlineWindow` falls back to
/// the busiest window and says why. The summary now makes the same fallback,
/// because the label and the row it belongs to must not disagree about whether
/// there is anything to say.
@Suite struct EveryAccountReachesTheMenuBar {

    private func snapshot(_ id: String, _ windows: [(String, Double)]) -> AccountSnapshot {
        AccountSnapshot(
            id: id, provider: id.hasPrefix("copilot") ? .copilot : .claude,
            displayName: id, planLabel: "—",
            windows: windows.map { LimitWindow(id: $0.0, percent: $0.1, resetsAt: nil) },
            freshness: .live(Date()), failure: nil)
    }

    private var monthly: AccountSnapshot { snapshot("copilot/1", [("premium", 61)]) }
    private var both: AccountSnapshot {
        snapshot("claude/1", [("session", 12), ("weekly", 44)])
    }

    @Test(arguments: [PrimaryWindow.worst, .session, .weekly])
    func anAccountWithNeitherNamedWindowStillHasALabel(window: PrimaryWindow) {
        let summary = menuBarSummary([monthly], now: Date(), window: window)
        #expect(summary?.percent == 61, """
            "\(window)" produced no label for an account whose only window is \
            monthly — the menu bar goes blank while the row below it draws
            """)
    }

    /// And the named window is still preferred where there is one.
    @Test func thechosenWindowStillWins() {
        #expect(menuBarSummary([both], now: Date(), window: .session)?.percent == 12)
        #expect(menuBarSummary([both], now: Date(), window: .weekly)?.percent == 44)
        #expect(menuBarSummary([both], now: Date(), window: .worst)?.percent == 44)
    }

    /// Mixed accounts: the one that answers the setting answers it, and the one
    /// that cannot falls back — and the busiest of the two is what shows.
    @Test func aMixedListTakesTheWorstOfWhatEachCanOffer() {
        let summary = menuBarSummary([both, monthly], now: Date(), window: .session)
        // 12 from Claude's five-hour, 61 from Copilot's fallback.
        #expect(summary?.percent == 61)
    }

    @Test func nothingAtAllIsStillNothing() {
        #expect(menuBarSummary([], now: Date(), window: .weekly) == nil)
        #expect(menuBarSummary([snapshot("copilot/2", [])], now: Date(), window: .weekly) == nil)
    }
}
