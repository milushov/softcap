import SwiftUI
import ProviderKit
import StatusUI
import Preferences
import Monitoring

struct PopoverView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var loc = Localization.shared

    /// A second hand for the countdowns: recomputes the remainder without
    /// touching the network.
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if model.preferences.minimalWindow { minimal } else { full }
        }
        .frame(width: 322)
        // The chosen language decides how a date and a time are written, not
        // only which words are used. Left alone, SwiftUI formats them in the
        // system's language while every label around them follows the setting —
        // so the badge said `28 Aug` in one language and the clock beside it
        // read in another.
        .environment(\.locale, loc.activeLocale)
        .environment(\.layoutDirection, loc.layoutDirection ?? .leftToRight)
        .id(loc.language)
        .onAppear { model.isPopoverOpen = true }
        .onDisappear { model.isPopoverOpen = false }
        .onReceive(tick) { now = $0 }
    }

    /// The window as it has always been: a heading, two meters per account,
    /// three named buttons.
    private var full: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)

            if model.snapshots.isEmpty {
                empty
            } else {
                ForEach(Array(model.snapshots.enumerated()), id: \.element.id) { index, snapshot in
                    AccountRow(
                        snapshot: snapshot, now: now,
                        layout: model.preferences.rowLayout,
                        showSnapshotAge: model.preferences.showSnapshotAge,
                        localization: loc
                    )
                    if index < model.snapshots.count - 1 { Divider().opacity(0.35) }
                }
            }

            Divider().opacity(0.5)
            footer
        }
    }

    /// The same window with everything that is not a reading taken off it.
    ///
    /// Nothing is drawn above the list unless the readings are overdue, and
    /// that line is the only heading this window ever spends: a clock saying
    /// when a current reading was taken answers a question nobody asked, while
    /// `2 h old` answers the one that matters.
    private var minimal: some View {
        VStack(spacing: 0) {
            if case .overdue(let seconds) = age {
                Text(String(format: loc("%@ old"), loc.remaining(seconds)))
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(Severity.hot.tint)
                    .help(loc("Nothing has been read for a while. A sign-in prompt may be waiting."))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 13)
                    .padding(.bottom, 2)
            }

            if model.snapshots.isEmpty {
                empty
            } else {
                ForEach(model.snapshots) { snapshot in
                    MinimalAccountRow(
                        snapshot: snapshot, now: now,
                        choice: model.preferences.primaryWindow,
                        showSnapshotAge: model.preferences.showSnapshotAge,
                        localization: loc
                    )
                }
            }

            quietFooter
        }
        .padding(.vertical, 8)
    }

    private var header: some View {
        HStack {
            Text(loc("Subscription limits")).font(.system(size: 12.5, weight: .semibold))
            Spacer()
            freshness
        }
        .padding(.horizontal, 13)
        .padding(.top, 11).padding(.bottom, 9)
    }

    /// When the figures were taken, and whether that is longer ago than it
    /// should be.
    ///
    /// The spinner is shown only while a poll is behaving. A poll can block on a
    /// keychain prompt and never return — that call cannot be cancelled — and the
    /// old header spun for as long as it lasted, which reads as "working on it"
    /// and was watched saying so for an hour. Past the point where the reading is
    /// overdue, the age replaces both the spinner and the clock time: `2:41 AM`
    /// is perfectly plausible and says nothing.
    /// How old the readings are, and whether that is older than the polling
    /// interval says it should be. Both windows ask, so it is asked once here
    /// rather than computed twice.
    private var age: ReadingAge {
        readingAge(
            lastUpdated: model.lastUpdated, now: now,
            pollingEvery: model.preferences.backgroundInterval
        )
    }

    @ViewBuilder
    private var freshness: some View {
        if case .overdue(let seconds) = age {
            Text(String(format: loc("%@ old"), loc.remaining(seconds)))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Severity.hot.tint)
                .help(loc("Nothing has been read for a while. A sign-in prompt may be waiting."))
        } else if model.isRefreshing {
            ProgressView().controlSize(.small)
        } else if let updated = model.lastUpdated {
            Text(updated, style: .time)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    /// What an empty window says.
    ///
    /// "Sign in to Claude Code" is the right advice exactly when it is not the
    /// problem. On a machine where Claude Code is signed in and the keychain has
    /// not been allowed — which is every machine before somebody allows it — the
    /// list is empty for a reason the reader has already dealt with, and being
    /// told to do it again is worse than being told nothing.
    private var empty: some View {
        VStack(spacing: 6) {
            if model.cliAccessBlocked {
                Text(loc("No accounts found")).font(.system(size: 12, weight: .medium))
                Text(loc("Claude Code's credentials cannot be read, so the account signed in there cannot be shown."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                Button(loc("Allow access…")) { Task { await model.refresh(.person) } }
                    .disabled(model.isRefreshing)
                    .padding(.top, 2)
            } else {
                Text(loc("No accounts found")).font(.system(size: 12, weight: .medium))
                Text(loc("Sign in to Claude Code or run Codex."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22)
    }

    private var footer: some View {
        HStack {
            Button(loc("Refresh")) { Task { await model.refresh(.person) } }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .keyboardShortcut("r")
            Spacer()
            Button(loc("Settings…")) { SettingsWindow.open() }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .keyboardShortcut(",")
            Spacer()
            Button(loc("Quit")) { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    /// Three symbols where the full window has three words. The actions are in
    /// the status item's menu as well, but a window whose only way out is a
    /// gesture nothing advertises is a window with no way out.
    private var quietFooter: some View {
        HStack {
            quietButton("arrow.clockwise", loc("Refresh"), "r") {
                Task { await model.refresh(.person) }
            }
            Spacer()
            quietButton("gearshape", loc("Settings…"), ",") { SettingsWindow.open() }
            Spacer()
            quietButton("power", loc("Quit"), "q") { NSApplication.shared.terminate(nil) }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
    }

    private func quietButton(
        _ symbol: String, _ title: String, _ key: KeyEquivalent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        // Without this the first of the three takes keyboard focus on opening
        // and macOS draws the accent-coloured focus fill behind it, which at
        // this size reads as somebody else's app icon sitting in the footer
        // rather than as a button that is ready. The shortcut still works.
        .focusEffectDisabled()
        .help(title)
        .accessibilityLabel(title)
        .keyboardShortcut(key)
    }
}
