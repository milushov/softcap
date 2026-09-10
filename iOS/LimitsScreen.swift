import SwiftUI
import ProviderKit
import Monitoring
import StatusUI

/// The limits list on the phone.
///
/// Rows come from `StatusUI` — the same ones the Mac window and the widget draw.
/// That is the whole point of the shared module: three surfaces cannot drift
/// apart if they share one view.
struct LimitsScreen: View {
    @ObservedObject var model: PhoneModel
    @ObservedObject private var loc = Localization.shared

    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Group {
                if model.snapshots.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .navigationTitle(loc("Subscription limits"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { freshness }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        if model.isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .accessibilityLabel(loc("Refresh"))
                }
            }
        }
        // The chosen language decides how a date and a time are written, not
        // only which words are used. Left alone, SwiftUI formats them in the
        // system's language while every label around them follows the setting —
        // so the badge said `28 Aug` in one language and the clock beside it
        // read in another.
        .environment(\.locale, loc.activeLocale)
        .environment(\.layoutDirection, loc.layoutDirection ?? .leftToRight)
        .id(loc.language)
        .onReceive(tick) { now = $0 }
        .refreshable { await model.refresh() }
    }

    private var list: some View {
        List(model.snapshots) { snapshot in
            AccountRow(
                snapshot: snapshot,
                now: now,
                layout: model.preferences.rowLayout,
                showSnapshotAge: model.preferences.showSnapshotAge,
                compactPadding: true,
                localization: loc
            )
        }
        .listStyle(.insetGrouped)
    }

    /// The phone has no Claude Code to sign into, so the wording differs from the
    /// Mac's: it points at the only thing that can actually help here.
    /// When the figures were taken, and whether that is longer ago than it
    /// should be.
    ///
    /// The model has published `lastUpdated` all along and nothing showed it, so
    /// the screen said nothing at all about the age of what it was showing —
    /// while the Mac window, built from the same modules, had a view for exactly
    /// this. A phone suspends: the numbers on screen can be an hour old before
    /// anything moves. Same words and same colour as the window, so the two do
    /// not describe the same fact differently.
    @ViewBuilder
    private var freshness: some View {
        // Nothing read, nothing to date. `lastUpdated` is set after every poll,
        // including one that found no accounts at all — so a fresh simulator
        // showed the current time above "No accounts found", which reads as
        // "these figures are current and there are none of them" rather than as
        // "nobody is signed in". The Mac window, in the same situation, shows the
        // two sentences and no time; this is the same fact stated the same way.
        if let updated = model.lastUpdated, !model.snapshots.isEmpty {
            let age = readingAge(
                lastUpdated: updated, now: now,
                pollingEvery: model.preferences.backgroundInterval
            )
            if case .overdue(let seconds) = age {
                Text(String(format: loc("%@ old"), loc.remaining(seconds)))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Severity.hot.tint)
            } else {
                Text(updated, style: .time)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label(loc("No accounts found"), systemImage: "gauge.with.needle")
        } description: {
            Text(loc("Sign in on your Mac — accounts sync through the keychain."))
        }
    }
}

// MARK: - previews

/// Sample data for previews. Real accounts live in the keychain and are absent
/// from a simulator, so without this the list layout could only be checked on a
/// device with a signed-in account.
private extension AccountSnapshot {
    static func sample(
        _ name: String, plan: String, session: Double, weekly: Double, stale: Bool = false
    ) -> AccountSnapshot {
        let now = Date()
        return AccountSnapshot(
            id: "claude/\(name)", provider: .claude, displayName: name, planLabel: plan,
            windows: [
                LimitWindow(id: "session", percent: session,
                            resetsAt: now.addingTimeInterval(2 * 3600 + 22 * 60)),
                LimitWindow(id: "weekly", percent: weekly,
                            resetsAt: now.addingTimeInterval(5 * 86400)),
            ],
            freshness: stale ? .snapshot(now.addingTimeInterval(-2 * 86400)) : .live(now),
            failure: nil
        )
    }
}

#Preview("With accounts") {
    LimitsScreen(model: PhoneModel.preview(accounts: [
        .sample("alex@example.com", plan: "Max 20x", session: 16, weekly: 25),
        .sample("sam@example.com", plan: "Max 5x", session: 78, weekly: 61),
        .sample("team@example.org", plan: "Pro", session: 96, weekly: 88),
    ]))
}

#Preview("Empty") {
    LimitsScreen(model: PhoneModel.preview(accounts: []))
}
