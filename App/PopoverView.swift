import SwiftUI
import AppKit
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

    /// Whether the keychain's question is on screen, and whether the last one
    /// came back with nothing changed. Held by the window rather than the model
    /// because they describe this window's own press: the settings screen runs
    /// the same repair and keeps its own pair for the same reason.
    @State private var opening = false
    @State private var openingFailed = false

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
        // A press that changed nothing is news about this visit to the window.
        // The view behind the popover is built once and kept, so the note
        // outlived every close: a refusal, a click elsewhere, and the next
        // opening of the window still carried the red line under the buttons —
        // reporting a press nobody had made since.
        .onChange(of: model.isPopoverOpen) { _, open in
            if !open { openingFailed = false }
        }
    }

    /// Whether any row carries the mark for the account in use.
    ///
    /// It follows the setting that put the figure in the menu bar. Under
    /// `Busiest` somebody has said they do not want this idea, and a dot
    /// still marking the account in use would be a leftover from a feature
    /// they turned off. Nil when nobody is named either — nothing has been
    /// seen to rise yet — so a fresh launch draws the list it always drew.
    private var marksRows: Bool {
        model.preferences.menuBarAccount == .inUse && model.accountInUse != nil
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
                        signIn: signIn(for: snapshot),
                        inUse: marksRows ? snapshot.id == model.accountInUse : nil
                    )
                    if index < model.snapshots.count - 1 { Divider().opacity(0.35) }
                }
            }

            pastedCodeField
            deviceCodeField
            if model.isDemo {
                Divider().opacity(0.35)
                demoNote
            }
            Divider().opacity(0.5)
            footer
        }
    }

    /// What says that the numbers above are invented.
    ///
    /// In both shapes of the window, including the minimal one — which is built
    /// to carry nothing that is not a reading, and pays a line for this. Showing
    /// somebody invented figures without saying so is the one thing worse than
    /// spending the line.
    private var demoNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
            Text(loc("Demo — sample data"))
                .font(.system(size: 10.5))
            Spacer()
            Button(loc("Sign in…")) {
                model.settingsSection = .accounts
                SettingsWindow.open()
            }
            .buttonStyle(.clickable)
            .font(.system(size: 10.5))
            .foregroundStyle(.tint)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 13)
        .padding(.vertical, 5)
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
                        signIn: signIn(for: snapshot),
                        inUse: marksRows ? snapshot.id == model.accountInUse : nil
                    )
                }
            }

            pastedCodeField
            deviceCodeField
            if model.isDemo { demoNote }
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
    /// An empty list that has been read has two causes, and they want opposite
    /// advice. No account has been added, which the browser fixes. Or the saved
    /// list was refused — the keychain binds access to the signature that wrote
    /// the item, so an update can be enough — and then every account is intact
    /// behind a question nobody has been asked yet.
    ///
    /// The window used to state the first one over both. To the second it read:
    /// your accounts are gone, go and sign in again — which is a conclusion
    /// drawn where the app has been refused the right to draw one, beside advice
    /// that spends a grant replacing a credential that still works. The store
    /// has told the two apart since 0.1.26 and the window simply never asked.
    ///
    /// Asking costs nothing and raises nothing: `load()` made that read at
    /// launch with the keychain's own dialog turned off, and `savedAccountsProblem`
    /// is the answer it already had. It is also what keeps this off a fresh
    /// install's screen — an item that was never written is not a refusal, and
    /// leaves that property `nil`.
    ///
    /// A third cause exists and gets its own screen a layer down: see
    /// `SavedAccountsProblem`, where what is said about each of the three is
    /// decided once for this window and the settings pane together.
    private var empty: some View {
        VStack(spacing: 6) {
            if model.lastUpdated == nil {
                Text(loc("Looking for your accounts…")).font(.system(size: 12, weight: .medium))
                Text(loc("Reading the keychain and asking each service."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
            } else if let reason = model.savedAccountsProblem {
                shut(SavedAccountsProblem(reason))
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

    /// The accounts are there and shut, and this is the way back in.
    ///
    /// The symbol is the one thing this window has that the settings pane does
    /// not spend: a column with nothing else in it, and four lines of
    /// explanation under a heading read as an error report without something
    /// above them saying which kind of trouble this is. A lock is shut, not
    /// broken.
    ///
    /// **Start over…** is not here. It deletes the only copy of every refresh
    /// token in the item, and this window opens under the pointer on a click of
    /// the menu bar — the two facts do not belong within a few pixels of each
    /// other. That button stays behind the settings screen's confirmation, and
    /// `Settings…` is how somebody who needs it gets there.
    @ViewBuilder
    private func shut(_ problem: SavedAccountsProblem) -> some View {
        Image(systemName: problem.symbol)
            .font(.system(size: 18))
            .foregroundStyle(problem.mayBeOpened ? Color.accentColor : Severity.hot.tint)
            .padding(.bottom, 4)
            // Decoration. The heading under it says the same thing in words,
            // and VoiceOver reading "lock, filled" before that sentence spends
            // the listener's first impression on an ornament.
            .accessibilityHidden(true)

        // The heading and its explanation are one thing said twice, so they sit
        // closer to each other than to anything else. At the surrounding stack's
        // spacing all four elements were equally far apart, and the symbol read
        // as a fourth line of text rather than as the thing the lines are about.
        VStack(spacing: 3) {
            Text(problem.heading).font(.system(size: 12, weight: .medium))

            Text(problem.explanation)
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
        }

        if problem.mayBeOpened {
            // The spinner replaces the button rather than sitting beside it.
            // The press puts a system dialog on screen and the answer is a
            // person's to give, so there is nothing to cancel and nothing else
            // to press — and a button still offering to do what is already
            // being done invites a second dialog for the same item.
            if opening {
                // Given the button's height rather than its own. Swapped for a
                // bare spinner the block lost six points at the moment of the
                // press, and everything under it — including the Settings…
                // beneath — jumped up under the pointer that had just pressed
                // something.
                ProgressView().controlSize(.small)
                    .frame(height: 22).padding(.top, 2)
            } else {
                Button(loc("Open saved accounts")) { Task { await askTheKeychain() } }
                    .padding(.top, 2)
            }
            Button(loc("Settings…")) { openAccounts() }
                .buttonStyle(.clickable)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else {
            Button(loc("Settings…")) { openAccounts() }
                .padding(.top, 2)
        }

        if openingFailed {
            Text(loc("That did not work, and nothing was changed."))
                .font(.system(size: 10.5)).foregroundStyle(Severity.hot.tint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
        }
    }

    /// Settings, opened on the screen this window is talking about.
    ///
    /// The footer's `Settings…` opens whichever section was last looked at,
    /// which is right for a button that means "settings". This one means the
    /// rest of what can be done about a list that will not open — the repair
    /// again, and **Start over…**, which is the only way out of the third
    /// reason and is deliberately not in this window. Landing on Appearance
    /// with that errand is a dead end the person has to find their own way out
    /// of.
    private func openAccounts() {
        model.settingsSection = .accounts
        SettingsWindow.open()
    }

    /// One press of the keychain's question.
    ///
    /// Named for what it does rather than for the model method it calls. It was
    /// `openSavedAccounts()`, the same name one line down with `model.` in
    /// front of it — which compiles, does the right thing, and is one dropped
    /// receiver away from calling itself forever.
    ///
    /// The note is spoken only when the reason is the same afterwards as it was
    /// before, which is the rule `AccountsPane.repair` already follows: an
    /// attempt that failed and nonetheless moved — the item opened, and what
    /// came out could not be understood — has rewritten the explanation above,
    /// and "nothing was changed" under a changed explanation is the one untrue
    /// line on the screen.
    private func askTheKeychain() async {
        opening = true
        openingFailed = false
        let before = model.savedAccountsProblem
        do {
            try await model.openSavedAccounts()
        } catch {
            openingFailed = model.savedAccountsProblem == before
        }
        opening = false
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

    /// The code this window's sign-in is waiting on, shown in this window.
    ///
    /// Same reason as the field above, arrived at from the other side. A device
    /// sign-in never sends anything back to us: the whole attempt *is* the code
    /// on screen, so a row here offering "Sign in…" and then showing the code
    /// only in settings would start something that can be finished nowhere the
    /// person is looking — worse than the pasted-code case, where at least the
    /// browser page holds the code too.
    ///
    /// Gated to this window for the same reason, and by the same test: one
    /// grant must not be offered by two screens at once.
    @ViewBuilder
    private var deviceCodeField: some View {
        if let grant = login.deviceGrant, login.request?.origin == .window {
            VStack(alignment: .leading, spacing: 5) {
                Text(loc("Enter this code on the page that opened:"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(grant.userCode)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                    Button(loc("Copy the code")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(grant.userCode, forType: .string)
                    }
                    .font(.system(size: 11))
                    Link(loc("Open the page"), destination: grant.verificationURL)
                        .font(.system(size: 11))
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
                .buttonStyle(.clickable)
                .font(.system(size: 11.5))
                .keyboardShortcut("r")
            Spacer()
            Button(loc("Settings…")) { SettingsWindow.open() }
                .buttonStyle(.clickable)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .keyboardShortcut(",")
            Spacer()
            Button(loc("Quit")) { NSApplication.shared.terminate(nil) }
                .buttonStyle(.clickable)
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
        .buttonStyle(.clickable(inset: CGSize(width: 6, height: 2)))
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
