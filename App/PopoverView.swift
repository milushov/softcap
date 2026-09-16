import SwiftUI
import ProviderKit
import StatusUI
import Preferences
import Monitoring

struct PopoverView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var loc = Localization.shared

    /// The sign-in, watched rather than merely read.
    ///
    /// It is a separate `ObservableObject` hanging off the model, and `AppModel`
    /// republishes nothing of its own, so observing the model announces none of
    /// its changes. This window reads four of them — whether an attempt is
    /// running, which row asked, what the last one said, whether a code is
    /// wanted — and drew all four without being told. Nothing was visibly
    /// broken, because the countdown's one-second tick redraws the window
    /// anyway: every state change simply arrived up to a second late, with no
    /// answer to a press in between, and the whole feature would have gone
    /// still the day that timer was slowed or taken away. `AccountsPane` takes
    /// the same object the same way.
    @ObservedObject private var login: LoginController

    init(model: AppModel) {
        self.model = model
        _login = ObservedObject(wrappedValue: model.login)
    }

    /// A second hand for the countdowns: recomputes the remainder without
    /// touching the network.
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// The code from the page, when a sign-in has come back asking for one.
    @State private var pastedCode = ""

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
        // Whether the window is open is the popover's own business, and
        // `StatusItemController` hears it first-hand as its delegate. Said from
        // here as well it was said wrongly: this view carries `.id(loc.language)`
        // two lines down, so picking a language rebuilds it — and SwiftUI puts
        // the replacement on screen before it takes the old one off, which left
        // the flag false while the window was plainly open. Polling then dropped
        // to the background interval in front of somebody watching it.
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
                        localization: loc,
                        signIn: signIn(for: snapshot)
                    )
                    if index < model.snapshots.count - 1 { Divider().opacity(0.35) }
                }
            }

            pastedCodeField
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
                        localization: loc,
                        signIn: signIn(for: snapshot)
                    )
                }
            }

            pastedCodeField
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
    /// Two different things, because an empty list has two different reasons,
    /// and stating the wrong one is worse than saying nothing.
    ///
    /// Nothing read yet is the first, and it used to be missing. The first poll
    /// after a fresh install reads the keychain and asks two services over the
    /// network; none of that has returned by the time somebody clicks the icon,
    /// and the window answered "No accounts found" — a conclusion, drawn in the
    /// one moment the app has not yet looked. It was read as written: installed,
    /// clicked, declared broken, a minute before the accounts arrived. The
    /// spinner in the header was already turning and lost the argument, as a
    /// control in the corner does against a sentence in the middle.
    ///
    /// `lastUpdated` is what tells the two apart: `nil` until a poll finishes,
    /// set even by one that found nothing.
    ///
    /// No spinner beside the text. The full window's header already turns one,
    /// and two in a window this size read as two separate things happening. The
    /// minimal window has no header and so shows none at all — which is the
    /// right way round for a window whose whole point is that everything except
    /// a reading has been taken off it. The sentence carries the meaning; the
    /// spinner only ever said the same thing less clearly.
    ///
    /// An empty list that has been read has exactly one cause now: no account
    /// has been added. There used to be a second — Claude Code's keychain item
    /// refusing to be read — and two different sentences to tell them apart.
    /// The app no longer opens that item, so the second cause cannot happen and
    /// the advice is one line: add an account, which means the browser.
    private var empty: some View {
        VStack(spacing: 6) {
            if model.lastUpdated == nil {
                Text(loc("Looking for your accounts…")).font(.system(size: 12, weight: .medium))
                Text(loc("Reading the keychain and asking each service."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
            } else {
                Text(loc("No accounts found")).font(.system(size: 12, weight: .medium))
                Text(loc("Add an account in Settings — Softcap opens your browser to sign in."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                Button(loc("Settings…")) { SettingsWindow.open() }
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22)
    }

    // MARK: - signing in on the spot

    /// What this window can do about a row that says a sign-in is required.
    ///
    /// The point of it: a dead token used to be a sentence in the window and a
    /// button on the settings screen, so reading the problem and fixing it were
    /// two different places. Here they are one.
    ///
    /// `nil` unless the failure is that one and the service is one this app can
    /// actually sign in to. `LoginController.providers` is that list, the
    /// controller refuses anything outside it, and a button that would be
    /// refused is worse than no button at all.
    private func signIn(for snapshot: AccountSnapshot) -> SignInOffer? {
        guard snapshot.failure?.kind == .needsLogin,
              LoginController.providers.contains(snapshot.provider) else { return nil }

        // Whether the sign-in in hand is the one this row asked for. Two
        // accounts of the same service both showing a spinner would be the
        // window claiming two sign-ins where the controller allows one.
        let mine = login.request?.account == snapshot.id
        let progress: SignInOffer.Progress =
            if !login.isRunning { .offered }
            else if !mine { .blocked }
            else if login.isSavingAccount { .saving }
            else { .running }

        return SignInOffer(
            progress: progress,
            // Not while the field below is asking for the code: that message is
            // the instruction for the field, and the same sentence in two
            // places on a window this size reads as two things having gone
            // wrong rather than one thing being explained.
            note: mine && !login.manualCodeExpected ? login.message : nil,
            start: {
                pastedCode = ""
                login.start(provider: snapshot.provider, from: .window, for: snapshot.id)
            },
            cancel: { login.cancel() }
        )
    }

    /// The way back in when the browser could not be given a door.
    ///
    /// A sign-in normally returns through a loopback listener and this is never
    /// seen. When the port cannot be taken — another copy of the app, another
    /// Codex sign-in — the provider shows the code on its page instead and it
    /// has to be pasted somewhere. Without this field that somewhere is the
    /// settings screen, which is the trip the row's button exists to save: the
    /// sign-in would start here and be finishable only there.
    ///
    /// Only for a sign-in this window asked for. One started from settings is
    /// answered on the screen that started it, and two fields bound to two
    /// strings both offering to finish the same attempt is a race over one
    /// grant.
    @ViewBuilder
    private var pastedCodeField: some View {
        if login.manualCodeExpected, login.request?.origin == .window {
            VStack(alignment: .leading, spacing: 5) {
                // The controller's own sentence rather than a fixed heading,
                // because it is not one sentence. It opens with the
                // instruction, and a code that is not the code from the page
                // replaces it with the correction — the one state where
                // `submit` deliberately keeps the attempt alive rather than
                // spending the grant. Printed as a heading of its own, that
                // correction had nowhere to appear: the row above suppresses
                // its note while this field is up.
                if let message = login.message {
                    Text(message)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    TextField(loc("Code from the page"), text: $pastedCode)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                    Button(loc("Done")) {
                        let code = pastedCode
                        Task {
                            await login.submit(code: code)
                            // Emptied only once the code has been taken. A
                            // mistyped one leaves the field asking again, and a
                            // field that wipes itself has thrown away the very
                            // thing that needed correcting.
                            if !login.manualCodeExpected { pastedCode = "" }
                        }
                    }
                    .font(.system(size: 11))
                    .disabled(pastedCode.isEmpty)
                }
            }
            .padding(.horizontal, 13)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
    }

    private var footer: some View {
        HStack {
            Button(loc("Refresh")) { Task { await model.refresh() } }
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
                Task { await model.refresh() }
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
