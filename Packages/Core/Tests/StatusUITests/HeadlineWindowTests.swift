import Testing
import Foundation
import ProviderKit
import Preferences
@testable import StatusUI

/// The account every suite here looks at: the same two windows, session the
/// fuller. One copy at file scope rather than one per suite, so the fixtures
/// cannot drift apart and a field added to `AccountSnapshot` is fixed once.
private func snapshot(_ windows: [LimitWindow]) -> AccountSnapshot {
    AccountSnapshot(
        id: "claude/one", provider: .claude,
        displayName: "name@example.com", planLabel: "Max 20x",
        windows: windows,
        freshness: .live(Date(timeIntervalSince1970: 0)), failure: nil
    )
}

private let session = LimitWindow(id: "session", percent: 88, resetsAt: nil)
private let weekly = LimitWindow(id: "weekly", percent: 23, resetsAt: nil)

/// The one-line row shows one limit, and this is the choice of which.
///
/// It falls back rather than showing nothing: a Codex account has whatever its
/// session files gave it, and a line that vanished because the requested window
/// is missing would read as a broken account rather than as a missing window.
@Suite struct WhichLimitTheLineShows {

    @Test func busiestTakesTheFullerWindow() {
        let account = snapshot([session, weekly])
        #expect(account.headlineWindow(for: .worst)?.id == "session")
    }

    @Test func askingForOneTakesThatOne() {
        let account = snapshot([session, weekly])
        #expect(account.headlineWindow(for: .weekly)?.id == "weekly")
        #expect(account.headlineWindow(for: .session)?.id == "session")
    }

    @Test func aMissingWindowFallsBackToWhatIsThere() {
        let account = snapshot([weekly])
        #expect(account.headlineWindow(for: .session)?.id == "weekly")
    }

    @Test func anAccountWithNoWindowsHasNoLine() {
        #expect(snapshot([]).headlineWindow(for: .worst) == nil)
    }
}

/// A click on the period label shows the row's other window, and only rows
/// that really have another window get the click at all.
@Suite struct PeekingAtTheOtherPeriod {

    @Test func theClickShowsTheOtherPeriod() {
        #expect(session.peekChoice == .weekly)
        #expect(weekly.peekChoice == .session)
    }

    @Test func twoPeriodsAreWorthAClick() {
        #expect(snapshot([session, weekly]).hasAnotherPeriod)
    }

    @Test func oneWindowHasNothingElseToShow() {
        #expect(!snapshot([session]).hasAnotherPeriod)
        #expect(!snapshot([weekly]).hasAnotherPeriod)
    }

    @Test func noWindowsHaveNothingToShowEither() {
        #expect(!snapshot([]).hasAnotherPeriod)
    }

    /// Going back is a forget, not a pin. Under `Busiest` the first click
    /// peeks at the other period; the click back lands on Busiest's own
    /// answer and leaves nothing, so the row follows the setting again when
    /// a later poll crowns the other window.
    @Test func clickingBackForgetsRatherThanPins() {
        let account = snapshot([session, weekly])
        #expect(account.peek(after: session, setting: .worst) == .weekly)
        #expect(account.peek(after: weekly, setting: .worst) == nil)
    }

    /// The same two clicks under an explicit setting: away is a peek, back
    /// is a forget.
    @Test func aClickAwayFromTheSettingIsAPeek() {
        let account = snapshot([session, weekly])
        #expect(account.peek(after: weekly, setting: .weekly) == .session)
        #expect(account.peek(after: session, setting: .weekly) == nil)
    }
}
