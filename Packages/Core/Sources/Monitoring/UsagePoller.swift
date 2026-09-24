import Foundation
import ProviderKit
import Preferences

public struct MenuBarSummary: Sendable, Hashable {
    public let percent: Double
    public let severity: Severity
    public let remaining: TimeInterval?
    /// The account the figure is about, or nil when it is about the whole list.
    ///
    /// Carried beside the figure rather than worked out again by whoever draws
    /// it: the spoken label names this account, and a name that disagreed with
    /// the number under it would be a lie told only to the person who cannot
    /// see the number.
    public let accountID: String?

    public init(
        percent: Double, severity: Severity,
        remaining: TimeInterval?, accountID: String? = nil
    ) {
        self.percent = percent
        self.severity = severity
        self.remaining = remaining
        self.accountID = accountID
    }
}

/// Walks the providers and collects the result. One provider's failure must
/// not hide the others, so everything is caught in place.
public actor UsagePoller {
    private let providers: [any UsageProvider]
    private var lastResult: [AccountSnapshot] = []

    public init(providers: [any UsageProvider]) {
        self.providers = providers
    }

    public func cached() -> [AccountSnapshot] { lastResult }

    public func refresh() async -> [AccountSnapshot] {
        var collected: [AccountSnapshot] = []

        for provider in providers {
            let refs: [AccountRef]
            do {
                refs = try await provider.discoverAccounts()
            } catch {
                // A provider that cannot even list its accounts used to be
                // skipped, so it vanished from the window with nothing to say
                // why. One row, naming the service and the trouble, is a poorer
                // answer than the accounts — and a far better one than an
                // absence nobody can ask about.
                collected.append(unavailable(provider.id, error: error))
                continue
            }
            for ref in refs {
                do {
                    collected.append(try await provider.fetch(ref))
                } catch {
                    collected.append(placeholder(for: ref, error: error))
                }
            }
        }

        lastResult = orderedForDisplay(collected)
        return lastResult
    }

    /// A provider that could not be asked at all. Named by the service, since
    /// there is no account to name.
    private func unavailable(_ provider: ProviderID, error: any Error) -> AccountSnapshot {
        let failure = error as? ProviderFailure
            ?? ProviderFailure(kind: .noData, diagnostic: "accounts could not be listed")
        return AccountSnapshot(
            id: "\(provider.rawValue)/unavailable", provider: provider,
            displayName: provider.title, planLabel: "—",
            windows: [], freshness: .live(Date()), failure: failure
        )
    }

    /// An account that yielded nothing still enters the list — otherwise it
    /// vanishes silently, which reads as "all is well".
    private func placeholder(for ref: AccountRef, error: any Error) -> AccountSnapshot {
        let failure = error as? ProviderFailure
            ?? ProviderFailure(kind: .network, diagnostic: "fetch failed")
        // The name the account was last known by, not its identifier. This is the
        // row a person reads when something is wrong, and it is the row that most
        // needs to say which account it is about — `claude/` and a UUID is the
        // one thing about the account they have never seen.
        //
        // The provider does the same when it can, but a provider that throws
        // before returning anything never gets there: the row is built here
        // instead, and this is where it was still showing the identifier.
        return AccountSnapshot(
            id: ref.id, provider: ref.provider,
            displayName: ref.lastKnownName.isEmpty ? ref.id : ref.lastKnownName,
            planLabel: "—",
            windows: [], freshness: .live(Date()), failure: failure
        )
    }
}

/// What to show in the menu bar.
///
/// Under `.busiest` the window closest to exhaustion across every account is
/// taken. Using the soonest reset would be wrong: for a free account it says
/// nothing.
///
/// Under `.inUse` the figure is about one account — the one `inUse` names, from
/// `ActiveAccountTracker`. It falls back to the behaviour above whenever there
/// is no account to speak for: nobody named, nobody by that name in this poll,
/// or an account carrying no windows because its reading failed. A menu bar
/// showing nothing is worse than a menu bar showing the neighbour for one poll.
public func menuBarSummary(
    _ snapshots: [AccountSnapshot], now: Date,
    window: PrimaryWindow = .worst,
    account: MenuBarAccount = .busiest,
    inUse: String? = nil
) -> MenuBarSummary? {
    if account == .inUse, let inUse,
       let snapshot = snapshots.first(where: { $0.id == inUse }),
       let chosen = snapshot.contribution(under: window) {
        return MenuBarSummary(
            percent: chosen.percent, severity: chosen.severity,
            remaining: chosen.remaining(from: now), accountID: snapshot.id
        )
    }

    let candidates = snapshots.compactMap { $0.contribution(under: window) }
    guard let worst = candidates.max(by: { $0.percent < $1.percent }) else { return nil }

    return MenuBarSummary(
        percent: worst.percent, severity: worst.severity, remaining: worst.remaining(from: now)
    )
}

private extension AccountSnapshot {
    /// The window this account offers under the `Primary window` rule.
    ///
    /// The fallback to the busiest window is the same one
    /// `AccountSnapshot.headlineWindow` makes for the row, and it has to be:
    /// without it an account reporting a monthly allowance matched neither
    /// filter, contributed nothing, and a person whose only accounts are of
    /// that kind got an empty menu bar above a window that was drawing their
    /// limits perfectly well — the label and the row disagreeing about whether
    /// there was anything to say.
    ///
    /// Asked once per account and used twice: by the branch that picks one
    /// account and by the one that ranks them all. Not shared with
    /// `headlineWindow` because that lives in `StatusUI`, which depends on this
    /// module and not the other way round.
    func contribution(under choice: PrimaryWindow) -> LimitWindow? {
        switch choice {
        case .worst:   peakWindow
        case .session: windows.first { $0.id == "session" } ?? peakWindow
        case .weekly:  windows.first { $0.id == "weekly" } ?? peakWindow
        }
    }
}
