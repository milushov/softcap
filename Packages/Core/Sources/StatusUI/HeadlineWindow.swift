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
