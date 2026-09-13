import Foundation
import AppKit
import OSLog
import SwiftUI
import UserNotifications
import ProviderKit
import ClaudeProvider
import CodexProvider
import Credentials
import Diagnostics
import Monitoring
import Preferences
import StatusUI
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshots: [AccountSnapshot] = []
    private static let log = Logger(subsystem: "app.softcap.Softcap", category: "poll")

    /// What each account was last logged as failing with, so an unchanged
    /// failure is not restated every five minutes.
    private var loggedFailures: [String: ProviderFailure.Kind] = [:]
    @Published private(set) var summary: MenuBarSummary?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?
    /// What the system allows, as opposed to what the settings ask for.
    @Published private(set) var notificationsPermitted = true
    /// Whether the keychain is refusing to let us see Claude Code's account.
    @Published private(set) var cliAccessBlocked = false

    /// Which settings screen to show. Published rather than held by the view:
    /// the menu bar opens that window through the system's ⌘, menu item and has
    /// no way to reach inside it otherwise.
    @Published var settingsSection: SettingsSection = .accounts

    /// How many Appearance screens are asking for the window to be on screen
    /// beside them, so a change can be seen rather than imagined.
    ///
    /// A count rather than a flag, because two of those screens overlap. Picking
    /// a language rebuilds the whole settings tree — `SettingsView` carries
    /// `.id(loc.language)` so that every string is read again — and SwiftUI puts
    /// the replacement on screen before it takes the old one off. A flag was set
    /// true by the arriving screen and then false by the departing one, so
    /// choosing a language closed the window while the screen that wanted it was
    /// still on show, and nothing was left to ask again. A count cannot be left
    /// that way round: it goes to two and back to one, and never reaches zero.
    ///
    /// Read by `StatusItemController`, which owns the window. It travels through
    /// the model rather than reaching for the controller directly, because the
    /// panes are built from settings and are handed no way to reach the status
    /// item — `settingsSection` above crosses the same gap, in the other
    /// direction, for the same reason.
    @Published private(set) var appearancePreviewRequests = 0

    func askForAppearancePreview() {
        appearancePreviewRequests += 1
    }

    /// Never below zero: a screen that went away without having asked — a state
    /// restoration, a rebuild this code has not met — would otherwise leave the
    /// count negative, and every later request would have to climb out of it
    /// before the window could appear again.
    func releaseAppearancePreview() {
        appearancePreviewRequests = max(0, appearancePreviewRequests - 1)
    }

    /// Shared by account management, browser sign-in and polling.
    let store: CredentialStore

    /// The browser sign-in.
    ///
    /// It used to be a `@StateObject` inside the Accounts pane, which made it
    /// unreachable from the menu and no longer-lived than the pane: leaving
    /// that section during a sign-in destroyed the controller and the sign-in
    /// with it. The delegate wires completion to preferences and the window,
    /// so returning from the browser never depends on a mounted settings pane.
    lazy var login = LoginController(store: store)

    func refreshAfterSignIn(_ ref: AccountRef) async {
        await identities.forget(ref.id)
        await refresh(.timer)
    }
    private var poller: UsagePoller?
    private var tracker = ThresholdTracker()

    /// The tracker holds a history of readings, so it is rebuilt only when the
    /// notification settings actually change — otherwise every visit to settings
    /// would erase the memory of previous values and swallow the next crossing.
    private var trackerSettings: TrackerSettings?

    private struct TrackerSettings: Equatable {
        let thresholds: [Int]
        let notifyOnRecovery: Bool
        let scope: WindowScope
        let quietHours: QuietHours?
    }

    /// How long a stored reading may be and still count as "the app was just
    /// running". Long enough to cover a relaunch or a crash, short enough that a
    /// transition from yesterday is not announced today.
    private static let baselineIsStaleAfter: TimeInterval = 15 * 60

    /// Restores the tracker's baseline from the snapshot the last run left on
    /// disk.
    ///
    /// Without it a relaunch is indistinguishable from a first run: the tracker
    /// has nothing to compare against, an account already past a threshold never
    /// produces a crossing, and the warning the app promises never arrives for
    /// that window — not late, never, until the limit resets and climbs again.
    private func seedTrackerFromDisk() {
        guard let stored = SharedStore.read() else {
            Self.log.info("no stored reading to restore the baseline from")
            return
        }
        let age = Date().timeIntervalSince(stored.capturedAt)
        guard age < Self.baselineIsStaleAfter else {
            Self.log.info("""
                the stored reading is \(Int(age / 60), privacy: .public) minutes old, too old to be a baseline
                """)
            return
        }
        tracker.seed(from: stored.accounts)
        // Once per launch, and the reason it is here at all: the restore is
        // otherwise invisible, and its absence was invisible for as long.
        Self.log.info("""
            baseline restored from a reading \(Int(age), privacy: .public)s old, \(stored.accounts.count, privacy: .public) accounts
            """)
    }

    private func rebuildTrackerIfNeeded() {
        let wanted = TrackerSettings(
            thresholds: preferences.thresholds,
            notifyOnRecovery: preferences.notifyOnRecovery,
            scope: preferences.notifyWindows,
            quietHours: preferences.quietHours
        )
        guard wanted != trackerSettings else { return }
        trackerSettings = wanted
        // Carried across, not started blank: changing the quiet hours is not a
        // reason to forget where every account stood, and forgetting means the
        // next reading has nothing below the threshold to have crossed from.
        let carried = tracker.baseline
        tracker = ThresholdTracker(
            thresholds: wanted.thresholds,
            notifyOnRecovery: wanted.notifyOnRecovery,
            scope: wanted.scope,
            quietHours: wanted.quietHours
        )
        tracker.restore(carried)
    }
    private let scheduler = PollScheduler()
    private let identities = ClaudeIdentityCache()
    /// Readings kept over time, so the statistics screen has something to draw.
    /// Its own file, not the snapshot: the snapshot is rewritten whole on every
    /// poll and a month of readings must not be.
    #if SCREENSHOTS
    /// No file at all in a screenshot build. `UsageHistoryStore` reads and
    /// writes nothing without a URL, so the month of real readings on this
    /// machine is neither drawn on the statistics screen nor overwritten by the
    /// fixtures merged in beside it.
    let history = UsageHistoryStore(url: nil)
    #else
    let history = UsageHistoryStore(url: SharedStore.historyURL)
    #endif

    private var started = false
    /// Whether a refresh was requested while the previous one was running.
    private var needsAnotherPass = false
    private var gate = RefreshGate()

    /// Once a minute while the window is open, once every five minutes in the
    /// background.
    /// Only a change restarts the poll. Written the same value twice it used to
    /// restart anyway, and a restart cancels the sleep that was already running
    /// and begins the interval again from zero — so a window told to open while
    /// it was open pushed the next reading a full minute further away. The
    /// preview beside the Appearance screen made that ordinary: it opens and
    /// closes the window on every switch between this app and another, and
    /// somebody moving back and forth faster than the interval was never read
    /// again. `preferences` below carries the same guard, for the same reason.
    var isPopoverOpen = false {
        didSet { if oldValue != isPopoverOpen { restartTimer() } }
    }

    /// Settings that affect polling and display. Supplied by the settings window.
    ///
    /// `@Published` because the window is drawn from it. A plain `var` on an
    /// `ObservableObject` announces nothing, and the window then keeps the
    /// shape that was chosen before last — which is how the minimal window
    /// arrived not working. `SettingsCopiesAnnounceThemselves` holds the rule
    /// for all three models that keep one of these.
    @Published var preferences: Preferences = .defaults {
        didSet {
            // Only when the cadence itself changed. It used to restart on any
            // settings change at all, which was harmless while a person was the
            // only one who could cause one — and then the update check began
            // stamping the moment it last ran into the same struct. Every check
            // cancelled the pending poll and started the interval again from
            // zero, so pressing "Check for updates" a few times inside one
            // background interval meant the usage poll never fired.
            if oldValue.foregroundInterval != preferences.foregroundInterval
                || oldValue.backgroundInterval != preferences.backgroundInterval {
                restartTimer()
            }

            let orderChanged = oldValue.ordering != preferences.ordering
                || oldValue.customAccountOrder != preferences.customAccountOrder
            if orderChanged {
                snapshots = orderedForDisplay(
                    snapshots, ordering: preferences.ordering,
                    customAccountOrder: preferences.customAccountOrder
                )
            }

            // The widget is another process and carries its own copy of these
            // four. It learned of a change when the snapshot was rewritten and
            // at no other time, and the snapshot was rewritten by a poll and by
            // nothing else — so the desktop kept the old row layout, and the
            // old language, for up to five minutes. `TheWidgetHearsAboutASettingChange`
            // holds this list to the one `publishToWidget` builds.
            //
            // Not before the first reading: publishing an empty list here would
            // blank a widget that had a good snapshot a moment ago.
            if lastUpdated != nil,
               oldValue.rowLayout != preferences.rowLayout
                || oldValue.showSnapshotAge != preferences.showSnapshotAge
                || oldValue.languageCode != preferences.languageCode
                || oldValue.backgroundInterval != preferences.backgroundInterval
                || orderChanged {
                publishToWidget(snapshots)
            }

            // Hiding an account, or switching a service off, is applied where
            // the poller is built — so the switch took effect at the next poll,
            // and until then the window went on showing what somebody had just
            // hidden. As a timer poll: flipping a switch in settings is the
            // machinery reacting, not a person pressing Refresh.
            if oldValue.hiddenAccounts != preferences.hiddenAccounts
                || oldValue.disabledProviders != preferences.disabledProviders {
                Task { await refresh(.timer) }
            }
            if oldValue.refreshHotKey != preferences.refreshHotKey {
                // Registration lives here, not in the settings scene: that one
                // is created lazily, so the shortcut did nothing until the window
                // was opened once.
                HotKeyCenter.shared.register(preferences.refreshHotKey, id: HotKeyID.refresh) {
                    Task { @MainActor [weak self] in await self?.refresh(.person) }
                }
            }
        }
    }

    init(
        store: CredentialStore = CredentialStore(
            keychain: SystemKeychain(), refresher: AnthropicTokenRefresher()
        )
    ) {
        self.store = store
    }

    /// True only where `SCREENSHOTS` is defined, which is `make screenshots` and
    /// nothing else. A plain `false` in every build that ships.
    #if SCREENSHOTS
    private let isScreenshotRun = true
    #else
    private let isScreenshotRun = false
    #endif

    /// Puts the store fixtures on screen. Empty unless this is a screenshot
    /// build, so the addresses in `ScreenshotFixtures` are in no shipped binary.
    private func seedScreenshotFixtures() async {
        #if SCREENSHOTS
        snapshots = ScreenshotFixtures.accounts
        // Derived the way a real poll derives it, rather than written out beside
        // the fixtures: a menu bar label that disagreed with the window below it
        // would be a lie told in a screenshot, and this is one line.
        summary = menuBarSummary(snapshots, now: Date(), window: preferences.primaryWindow)
        lastUpdated = Date()
        // The statistics screen draws the history rather than the snapshots, so
        // it needs its own fixtures — otherwise that screen alone would show the
        // real month of readings this machine has recorded.
        await history.merge(ScreenshotFixtures.samples, now: Date())
        #endif
    }

    func start() async {
        guard !started else { return }
        started = true

        // A screenshot build stops here, before the first thing is read or
        // written: no credential store, no keychain, no timers, no file watcher
        // and no widget snapshot. The machine this is built on holds four real
        // accounts, and a store listing is permanent — so the screenshot run is
        // not trusted to merely avoid the real data, it is unable to reach it.
        if isScreenshotRun {
            await seedScreenshotFixtures()
            return
        }

        await requestNotificationPermission()
        seedTrackerFromDisk()
        await store.load()

        // Everything that keeps the app working is armed before the first poll,
        // not after it. A poll can block indefinitely — a keychain read waits on
        // a system prompt, and that call cannot be cancelled — and when it did,
        // this method never reached its second half: no timer, no file watcher,
        // no hot key, no wake handler. One unanswered prompt at launch left the
        // app running and inert, showing whatever it had, for as long as it was
        // open. Seen twice; the second time it had been still for twenty-five
        // minutes.
        restartTimer()
        // The same origin as the re-registration in `didSet`: a hot key is a
        // person's finger. The two registrations disagreed once, and which
        // behaviour a press got depended on whether the shortcut had ever
        // been changed in settings.
        HotKeyCenter.shared.register(preferences.refreshHotKey, id: HotKeyID.refresh) {
            Task { @MainActor [weak self] in await self?.refresh(.person) }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.preferences.refreshAfterWake else { return }
                await self.refresh(.timer)
            }
        }

        // The first poll runs on its own, so a hang cannot take startup with it.
        // The timer above is already ticking, and `RefreshGate` lets a later tick
        // past a poll that has been stuck too long — so the app recovers by
        // itself the moment whatever blocked it lets go.
        Task { await refresh(.timer) }
    }

    /// `origin` decides one thing: whether this poll may put the keychain's
    /// access dialog on screen. The table lives on `PollOrigin`, where a test
    /// holds it: only the Allow access… button's origin answers yes.
    func refresh(_ origin: PollOrigin) async {
        await store.setPromptAllowed(origin.mayRaiseTheKeychainDialog)
        defer { Task { await store.setPromptAllowed(false) } }
        await poll()
    }

    private func poll() async {
        // A repeat call during a poll is remembered rather than dropped:
        // otherwise an update from the Codex file watcher was lost whenever it
        // coincided with a network poll, and new readings waited for the next
        // tick — up to five minutes. That defeated the whole point of instant
        // updates.
        // A poll that never returns must not stop every poll after it. The flag
        // this replaced was set on entry and cleared on the way out, which is
        // correct only if the way out is reached — a blocking keychain read does
        // not reach it, and the app then showed the same reading until it was
        // restarted, with nothing on screen to say why.
        let now = Date()
        if gate.wouldDisplace(at: now) {
            Self.log.error("a poll has been running for over 90s; starting another")
        }
        guard let run = gate.begin(at: now) else { needsAnotherPass = true; return }
        isRefreshing = true
        defer {
            // Takes its own permit: a poll displaced for hanging may still return
            // long afterwards, and must not open the gate on whatever replaced it.
            gate.end(run)
            isRefreshing = false
        }

        // The CLI is reconciled before a poll only while something still depends
        // on it: that is how an account just signed into gets picked up, and how
        // the copy of its refresh token stays current while it is still active.
        //
        // Once every account carries a grant of this app's own there is nothing
        // in Claude Code's keychain item the app does not already have, and
        // opening it is all cost. macOS checks a foreign item against its access
        // list on every read, and the grant that check looks for does not survive
        // the item's owner rewriting it — which Claude Code does each time it
        // refreshes, about every eight hours. Skipping the read is what turns
        // "allow once at setup" into something that is actually true.
        //
        // The person pressing "Allow access…" is the exception: they are
        // importing the CLI's account, and the dialog lands while they are
        // watching for it. A plain Refresh is not that person. It used to be —
        // any poll a person started could open the item — and with all four
        // accounts holding grants of their own, every press of Refresh asked
        // for the login keychain password, for an item nothing needed.
        //
        // Both conditions are read before the test rather than inside it: `||`
        // takes its right side as an autoclosure, which cannot be awaited in.
        let somethingStillNeedsTheCLI = await store.dependsOnCLI()
        let personGrantingAccess = await store.isPromptAllowed
        if somethingStillNeedsTheCLI || personGrantingAccess {
            await syncWithCLI()
        } else {
            // Nothing depends on Claude Code's item any more, so nothing is
            // blocked on it. `cliAccessBlocked` is only ever assigned inside
            // `syncWithCLI`, so skipping that call would freeze the flag at
            // whatever the last poll left — and a reader who fixed the problem by
            // signing every account in would go on being told, by the Accounts
            // screen and the empty state both, that credentials cannot be read.
            cliAccessBlocked = false
        }
        await rebuildPoller()

        guard let poller else { return }
        let result = orderedForDisplay(
            await poller.refresh(), ordering: preferences.ordering,
            customAccountOrder: preferences.customAccountOrder
        )
        // A failed account shows one translated sentence; the diagnostic behind
        // it exists for this line and had nowhere to go.
        //
        // Written when the failure starts or changes, not on every poll. Two
        // accounts needing a sign-in used to put the same pair of lines in the
        // log every five minutes — five hundred and seventy-six a day for a
        // condition that is already on screen and is not changing — and the next
        // genuinely new error would arrive into that. `ThresholdTracker` makes
        // the same argument about notifications a few lines below: once per
        // crossing, not once per poll.
        var stillFailing: [String: ProviderFailure.Kind] = [:]
        for account in result {
            guard let failure = account.failure else { continue }
            stillFailing[account.id] = failure.kind
            guard loggedFailures[account.id] != failure.kind else { continue }
            Self.log.error("""
                \(account.id, privacy: .public): \
                \(failure.diagnostic, privacy: .public)
                """)
            // The collector hears it too, on the same once-per-change terms.
            // An account dying used to leave no trace anywhere but this log —
            // two died in one afternoon and the investigation had to be run
            // from usage-history gaps. The report carries the diagnostic and
            // not the account: which one it was is personal, that it happens
            // is the signal.
            Task { await Diagnostics.shared.report(failure, category: "poll") }
        }
        // And once when it clears, so the log says how long it lasted rather
        // than simply stopping.
        for (id, _) in loggedFailures where stillFailing[id] == nil {
            Self.log.error("\(id, privacy: .public): answering again")
        }
        loggedFailures = stillFailing
        snapshots = result
        await history.record(result, at: Date())
        summary = menuBarSummary(result, now: Date(), window: preferences.primaryWindow)
        lastUpdated = Date()

        publishToWidget(snapshots)
        rebuildTrackerIfNeeded()
        let events = tracker.events(for: result, now: Date())
        // The reading is fed to the tracker even with notifications off:
        // otherwise turning them on would deliver a batch of stale events.
        if preferences.notificationsEnabled {
            for event in events { post(event) }
        }

        if needsAnotherPass {
            needsAnotherPass = false
            await poll()
        }
    }

    /// Asks Anthropic who is signed in to the CLI and hands the answer to the store.
    /// Reconciles with whatever account Claude Code is signed into.
    ///
    /// The keychain refusing to be read without a dialog is kept rather than
    /// swallowed. It is the normal answer when permission has not been granted,
    /// and its effect is that an account signed into with `/login` never appears
    /// — while the Accounts screen goes on promising that it will. Every other
    /// reason to give up here is ordinary: the CLI may simply not be signed in.
    private func syncWithCLI() async {
        let token: String
        do {
            token = try await store.currentCLIToken()
            cliAccessBlocked = false
        } catch let failure as ProviderFailure where failure.kind == .needsPermission {
            cliAccessBlocked = true
            return
        } catch {
            cliAccessBlocked = false
            return
        }
        let headers = [
            "Authorization": "Bearer \(token)",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": OAuthEndpoints.userAgent,
        ]
        guard
            let url = URL(string: "https://api.anthropic.com/api/oauth/profile"),
            let (data, code) = try? await URLSessionHTTPClient().get(url, headers: headers),
            code == 200,
            let profile = try? ClaudeProfileResponse.parse(data)
        else { return }

        // Not swallowed. This call is how an account keeps a copy of its refresh
        // token while it is still the active one, and that copy is the whole
        // reason a plan stays visible after `/login` moves on. A failure here is
        // invisible until the switch happens, and by then the account is gone
        // for good — which this project has watched happen once already.
        //
        // The next poll tries again, so a passing failure costs nothing. A
        // lasting one has no separate warning of its own: it means the app
        // cannot write its own keychain item, and reading it would be failing
        // too, which the rows already say.
        do {
            try await store.syncWithCLI(
                profileUUID: profile.uuid, displayName: profile.displayName
            )
        } catch {
            Self.log.error("""
                could not keep the CLI account's token copy: \
                \(String(describing: error), privacy: .public)
                """)
        }
    }

    private func rebuildPoller() async {
        let refs = await store.knownRefs()
            .filter { !preferences.hiddenAccounts.contains($0.id) }

        var providers: [any UsageProvider] = []
        if !preferences.disabledProviders.contains(.claude) {
            // The cache is held here, not by the provider: the provider is a value
            // rebuilt before every poll, and a cache rebuilt with it would never hit.
            providers.append(ClaudeUsageProvider(
                tokens: store, knownAccounts: refs, identities: identities
            ))
        }
        if !preferences.disabledProviders.contains(.codex) {
            providers.append(CodexLiveUsageProvider(tokens: store, knownAccounts: refs))
        }
        poller = UsagePoller(providers: providers)
    }

    /// Re-armed whenever the window opens or closes, because the interval
    /// differs between the two. `PollScheduler` keeps that from reaching a poll
    /// already running: it used to, and the requests in flight were cancelled —
    /// so opening the window to look at the accounts was what stopped them
    /// loading.
    private func restartTimer() {
        // The other door into polling, and the one `start()`'s screenshot guard
        // does not cover: opening the window re-arms the timer through
        // `isPopoverOpen`'s `didSet`, which would then replace the fixtures with
        // this machine's real accounts a minute after the first screenshot.
        if isScreenshotRun { return }

        let interval = isPopoverOpen
            ? preferences.foregroundInterval
            : preferences.backgroundInterval
        scheduler.restart(every: interval) { [weak self] in
            await self?.refresh(.timer)
        }
    }

    func accountRows() async -> [AccountsPane.AccountRow] {
        // The Accounts screen has its own path to the data — the keychain — and a
        // screenshot build must not reach it, so the fixtures answer here too.
        #if SCREENSHOTS
        if isScreenshotRun { return ScreenshotFixtures.rows }
        #endif

        await store.accountStates().map { item in
            AccountsPane.AccountRow(
                id: item.account.id,
                handle: item.account.handle,
                provider: item.account.provider,
                displayName: item.account.displayName,
                state: item.state
            )
        }
    }

    func forgetAccount(id: String) async throws {
        try await store.forget(id: id)
        await identities.forget(id)
        // `.timer`: the person asked to forget an account, not to be asked for
        // permission to read one.
        await refresh(.timer)
    }

    func forgetAllAccounts() async {
        for ref in await store.knownRefs() {
            try? await store.forget(id: ref.id)
        }
        await refresh(.timer)
    }

    /// Without permission the system silently drops every notification and
    /// returns the error in a closure that is easy to ignore. We ask once on
    /// first launch; after that the system remembers the answer.
    /// Asks once, then records what the system said.
    ///
    /// The answer used to be discarded. Denied — or never answered, which is
    /// what happens when the prompt appears behind other windows for an app with
    /// no Dock icon — the app went on posting notifications that went nowhere,
    /// while the settings screen showed the feature switched on. The switch was
    /// telling the truth about the app's intention and nothing about the result.
    private func requestNotificationPermission() async {
        let centre = UNUserNotificationCenter.current()
        _ = try? await centre.requestAuthorization(options: [.alert, .sound])
        await refreshNotificationAuthorization()
    }

    /// Re-read whenever the settings screen appears: the answer can change in
    /// System Settings at any time, without the app being told.
    func refreshNotificationAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsPermitted = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    /// Writes the snapshot to shared storage and asks the system to redraw the
    /// widget. A widget is a separate process and does not fetch data itself.
    private func publishToWidget(_ accounts: [AccountSnapshot]) {
        SharedStore.write(SharedSnapshot(
            accounts: accounts,
            capturedAt: lastUpdated ?? Date(),
            rowLayout: preferences.rowLayout,
            showSnapshotAge: preferences.showSnapshotAge,
            languageCode: preferences.languageCode,
            pollingEvery: preferences.backgroundInterval
        ))
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func post(_ event: ThresholdEvent) {
        // The words live with the catalogues in `StatusUI`, and they name the
        // window the event is about. Both limits crossed the same 80% within
        // one evening, and the two notifications read identically — reported,
        // reasonably, as the app repeating itself.
        let content = UNMutableNotificationContent()
        content.title = Localization.shared.notificationTitle(for: event)
        content.body = Localization.shared.notificationBody(for: event)
        let request = UNNotificationRequest(
            identifier: "\(event.accountID)/\(event.windowID)/\(event.kind)",
            content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            guard let error else { return }
            // Losing notifications silently is not acceptable: that is exactly
            // how this branch stayed broken — permission was never requested and
            // the error was discarded.
            NSLog("Softcap: notification not delivered — \(error.localizedDescription)")
        }
    }
}
