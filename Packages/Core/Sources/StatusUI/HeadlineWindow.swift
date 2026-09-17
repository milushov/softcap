import ProviderKit
import Preferences

public extension AccountSnapshot {
    /// The limit a one-line row shows, chosen by the "Primary window" setting.
    ///
    /// It lives here rather than in `Monitoring`, which makes a similar choice
    /// *across* accounts for the menu bar label: that answers "which account is
    /// the headline", this answers "which of one account's limits is", and
    /// folding them together would tie the window's layout to the menu bar's.
    ///
    /// The fallback is deliberate. An account carries whichever windows the
    /// service reported for it, and a row that disappeared because the
    /// requested window is absent would read as a broken account.
    func headlineWindow(for choice: PrimaryWindow) -> LimitWindow? {
        switch choice {
        case .worst:   peakWindow
        case .session: windows.first { $0.id == "session" } ?? peakWindow
        case .weekly:  windows.first { $0.id == "weekly" } ?? peakWindow
        }
    }
}

public extension LimitWindow {
    /// The choice that shows the other period than this window.
    ///
    /// Two branches, not three: window identifiers are a closed set —
    /// `Models.swift` names `session` and `weekly`, and both providers
    /// normalise to them.
    var peekChoice: PrimaryWindow { id == "session" ? .weekly : .session }
}

public extension AccountSnapshot {
    /// Whether a row has another period to peek at: the two choices resolve
    /// to different windows. One-window accounts fall back to the same
    /// window under either choice and answer no, so the label above them
    /// stays plain text rather than a button that changes nothing.
    var hasAnotherPeriod: Bool {
        headlineWindow(for: .session)?.id != headlineWindow(for: .weekly)?.id
    }

    /// What a click on `window`'s label leaves in the row: the choice showing
    /// the other period, or nothing when that choice resolves to the window
    /// the setting already shows. Going back is a forget rather than a pin —
    /// under `Busiest` a row clicked away and back keeps following the fuller
    /// window as polls move it, instead of freezing on the one it was shown.
    func peek(after window: LimitWindow, setting choice: PrimaryWindow) -> PrimaryWindow? {
        let flipped = window.peekChoice
        return headlineWindow(for: choice)?.id == headlineWindow(for: flipped)?.id
            ? nil : flipped
    }
}
