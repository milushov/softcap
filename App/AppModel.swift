import Foundation
import AppKit
import OSLog
import SwiftUI
import UserNotifications
import ProviderKit
import ClaudeProvider
import CodexProvider
import CopilotProvider
import ZaiProvider
import KimiProvider
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
    /// The account being worked with, or nil while nothing has been seen to
    /// rise. The menu bar draws its figure from it under `menuBarAccount ==
    /// .inUse`, and the window marks its row.
    @Published private(set) var accountInUse: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?
    /// What the system allows, as opposed to what the settings ask for.
    @Published private(set) var notificationsPermitted = true

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
        await refresh()
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
        guard let stored = SharedStore.readLocal() else {
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

    /// Fed by every poll, seeded from the history at the first one. A value
    /// type held here rather than behind an actor: it is read on the main actor
    /// while the summary is built, and a hop would put the figure and the name
    /// it belongs to one await apart.
    private var activity = ActiveAccountTracker()
    private var activitySeeded = false

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
    @Published var isPopoverOpen = false {
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

            // Both of these change what the figure means, and neither reached
            // the menu bar until a poll rewrote the summary — up to five
            // minutes of a setting that appears not to work. `Primary window`
            // has had that delay since it was added; the new one would have
            // inherited it.
            if oldValue.primaryWindow != preferences.primaryWindow
                || oldValue.menuBarAccount != preferences.menuBarAccount {
                summary = menuBarSummary(
                    snapshots, now: Date(), window: preferences.primaryWindow,
                    account: preferences.menuBarAccount, inUse: accountInUse
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
                Task { await refresh() }
            }
            if oldValue.demoMode != preferences.demoMode { syncDemo() }
            if oldValue.refreshHotKey != preferences.refreshHotKey {
                // Registration lives here, not in the settings scene: that one
                // is created lazily, so the shortcut did nothing until the window
                // was opened once.
                HotKeyCenter.shared.register(preferences.refreshHotKey, id: HotKeyID.refresh) {
                    Task { @MainActor [weak self] in await self?.refresh() }
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

    // MARK: - Demo

    /// When the demo clock started. Every demo value is a function of the time
    /// since this moment, so there is no simulation state to start, stop,
    /// restore after a sleep, or find disagreeing with itself.
    private var demoStartedAt = Date()
    /// Redraws the samples once a second while demo is on, and does not exist
    /// otherwise — somebody who never sees this mode pays nothing for it.
    private var demoTimer: Task<Void, Never>?
    /// Frames drawn since the widget was last told. The window moves at 1 Hz;
    /// the widget is a separate process on a battery and hears once a minute.
    private var demoFrames = 0
    /// How many accounts the last real poll found. `isDemo` asks this rather
    /// than `snapshots`, which during demo holds the samples and would answer
    /// that there are always three.
    private var realAccountCount = 0
    /// Whether a real poll has finished. Answering before the first reading
    /// would put samples in front of somebody who has accounts, for the second
    /// or two it takes to read them.
    private var hasPolled = false

    /// A history the demo draws from, held in memory with no file behind it.
    /// The real one is not touched: merging samples into it would overwrite a
    /// month of somebody's own readings with invented ones.
    private let demoHistory = UsageHistoryStore(url: nil)

    /// Whether sample accounts are on screen.
    var isDemo: Bool {
        if let chosen = preferences.demoMode { return chosen }
        return hasPolled && realAccountCount == 0
    }

    /// The history the statistics screen should draw.
    ///
    /// Keyed off the timer rather than off `isDemo`, so that the screenshot lane
    /// — which turns the mode on but never starts the timer — goes on drawing
    /// the month it seeded for itself.
    var visibleHistory: UsageHistoryStore { demoTimer != nil ? demoHistory : history }

    /// Starts or stops the demo to match `isDemo`. Safe to call repeatedly.
    private func syncDemo() {
        // A screenshot must not animate. That lane turns the mode on so the
        // Accounts screen shows the switch in the position its rows imply, and
        // seeds the launch frame itself — where every figure is the landing's,
        // before the demo clock has moved any of them.
        if isScreenshotRun { return }

        if isDemo {
            guard demoTimer == nil else { return }
            demoStartedAt = Date()
            demoFrames = 0
            Task { await demoHistory.merge(DemoData.samples(now: Date()), now: Date()) }
            demoTimer = Task { [weak self] in
                while !Task.isCancelled {
                    self?.drawDemoFrame()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        } else {
            guard demoTimer != nil else { return }
            demoTimer?.cancel()
            demoTimer = nil
            // In the same turn, not at the next poll. Left to the poll, the
            // desktop would go on naming sam.k@example.com for up to five
            // minutes after the person signed in as themselves.
            snapshots = []
            summary = nil
            publishToWidget([])
            Task { await refresh() }
        }
    }

    /// One frame of the demo.
    ///
    /// `resetsAt` is re-stamped every second against the demo remainder, which
    /// is what makes a countdown read 41m at launch and lose a minute every
    /// second afterwards. No view is changed for this mode; they all go on
    /// computing `resetsAt - now` as they always have.
    private func drawDemoFrame() {
        let now = Date()
        let rows = orderedForDisplay(
            DemoData.snapshots(since: demoStartedAt, now: now),
            ordering: preferences.ordering,
            customAccountOrder: preferences.customAccountOrder
        )
        snapshots = rows
        // `inUse: nil` on purpose, like the threshold tracker below: the sample
        // accounts are a function of the demo clock, so feeding them in would
        // have the figure hop between invented accounts every few seconds. With
        // nobody named the figure ranks the list, which is what the demo showed
        // before this setting existed.
        summary = menuBarSummary(
            rows, now: now, window: preferences.primaryWindow,
            account: preferences.menuBarAccount, inUse: nil
        )
        lastUpdated = now

        // The tracker is deliberately not fed. One sample sits at a hundred
        // percent and would otherwise deliver a notification within seconds of
        // a first launch, about an account nobody has.
        if demoFrames % 60 == 0 { publishToWidget(rows) }
        demoFrames += 1
    }

    /// Puts the store fixtures on screen. Empty unless this is a screenshot
    /// build — not because the data is secret, since `DemoData` ships now, but
    /// because a screenshot run must reach no keychain, no timer and no file.
    private func seedScreenshotFixtures() async {
        #if SCREENSHOTS
        // The launch frame of the demo: `since` and `now` being the same moment
        // is what makes every figure the landing's exactly, before the demo
        // clock has moved any of them. A screenshot must not animate.
        snapshots = DemoData.snapshots(since: Date(), now: Date())
        // Derived the way a real poll derives it, rather than written out beside
        // the fixtures: a menu bar label that disagreed with the window below it
        // would be a lie told in a screenshot, and this is one line.
        summary = menuBarSummary(
            snapshots, now: Date(), window: preferences.primaryWindow,
            account: preferences.menuBarAccount, inUse: nil
        )
        lastUpdated = Date()
        // The statistics screen draws the history rather than the snapshots, so
        // it needs its own fixtures — otherwise that screen alone would show the
        // real month of readings this machine has recorded.
        await history.merge(DemoData.samples(now: Date()), now: Date())
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

        // Said once, at launch, and said in full. The log used to record a
        // sign-in failing because the account list was unreadable, and never
        // once record why the list was unreadable — so the one number that
        // identifies which of the two it is, and which build wrote the item,
        // was the one thing missing from the only evidence there is.
        if let reason = await store.whyUnreadable() {
            let detail = await store.unreadableDiagnostic ?? "no detail"
            Self.log.error("""
                account list unreadable: \(String(describing: reason), privacy: .public) \
                — \(detail, privacy: .public)
                """)
        }

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
            Task { @MainActor [weak self] in await self?.refresh() }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.preferences.refreshAfterWake else { return }
                await self.refresh()
            }
        }

        // The first poll runs on its own, so a hang cannot take startup with it.
        // The timer above is already ticking, and `RefreshGate` lets a later tick
        // past a poll that has been stuck too long — so the app recovers by
        // itself the moment whatever blocked it lets go.
        Task { await refresh() }
    }

    /// A poll, whoever asked for it.
    ///
    /// This used to take a `PollOrigin`, whose whole job was to decide whether
    /// the poll might put the keychain's access dialog on screen. No poll opens
    /// another app's keychain item any more, so no poll can raise that dialog,
    /// and there is nothing left for the caller to say.
    func refresh() async {
        await poll()
    }

    private func poll() async {
        // A repeat call during a poll is remembered rather than dropped:
        // otherwise a press of Refresh, a wake, or a hot key that lands while a
        // poll is in flight is lost, and the reading it asked for waits for the
        // next tick — up to five minutes after somebody asked for it now.
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

        await rebuildPoller()

        // Read once, here, and used twice: the window draws from it and the
        // widget guard below turns on it. Two reads of the same fact in one
        // poll can disagree — a button can answer the keychain between them —
        // and then the window and the widget are deciding from different
        // answers within the same pass.
        //
        // It is not read early to get the window off "No accounts found"
        // sooner: `empty` asks `lastUpdated == nil` first and says it is still
        // looking until this poll finishes, which is the order
        // `itAsksWhetherAPollHasFinishedFirstOfAll` holds it to. During the
        // first poll nothing reads this.
        savedAccountsProblem = await accountsProblem()

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
        realAccountCount = result.count
        hasPolled = true

        // A poll goes on running while samples are on screen — that is what
        // lets somebody press Add Account from a demo window and have the mode
        // end the moment the account arrives. What it must not do is put its
        // own findings on screen, record them, or announce them.
        if isDemo {
            syncDemo()
            if needsAnotherPass {
                needsAnotherPass = false
                await poll()
            }
            return
        }
        syncDemo()

        snapshots = result
        let at = Date()
        await history.record(result, at: at)

        // Seeded here rather than at init, and after the readings are recorded:
        // the history lives behind an actor, and the marks have to be in place
        // before this poll is measured against them. Recording first is what
        // makes the first poll of a launch honest either way — a rise the
        // thinning rule kept is credited by the seed, one it dropped is caught
        // by the comparison below, and neither is counted twice.
        if !activitySeeded {
            activitySeeded = true
            activity = ActiveAccountTracker(seededFrom: await history.current())
        }
        activity.observe(result, at: at)
        accountInUse = activity.accountInUse

        summary = menuBarSummary(
            result, now: at, window: preferences.primaryWindow,
            account: preferences.menuBarAccount, inUse: accountInUse
        )
        lastUpdated = at

        // A reading of nothing is published. A reading of nothing arrived at
        // because the app could not look is not.
        //
        // An account list this build cannot open polls as no accounts at all,
        // and handing that to the widget replaces real numbers with "No
        // accounts found" — said about accounts that are still there, on a
        // surface with no room to explain itself and nothing to press. The last
        // good reading stays instead, with the age the widget already shows,
        // and the repair in Accounts is what puts a new one there.
        let listWasRead = savedAccountsProblem == nil
        if listWasRead || !snapshots.isEmpty {
            publishToWidget(snapshots)
        }
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
        if !preferences.disabledProviders.contains(.copilot) {
            providers.append(CopilotUsageProvider(tokens: store, knownAccounts: refs))
        }
        if !preferences.disabledProviders.contains(.glm) {
            providers.append(ZaiUsageProvider(tokens: store, knownAccounts: refs))
        }
        if !preferences.disabledProviders.contains(.kimi) {
            providers.append(KimiUsageProvider(tokens: store, knownAccounts: refs))
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
            await self?.refresh()
        }
    }

    func accountRows() async -> [AccountsPane.AccountRow] {
        // The Accounts screen has its own path to the data — the keychain — and a
        // screenshot build must not reach it, so the fixtures answer here too.
        #if SCREENSHOTS
        if isScreenshotRun { return DemoData.rows }
        #endif

        // The same reason the screenshot lane has: this screen reads the
        // keychain, and in demo there may be no item to read — asking would
        // raise a system prompt in front of somebody who has signed in to
        // nothing.
        if isDemo { return DemoData.rows }

        // Written out rather than left implicit: a single-expression body
        // returns on its own, and the `#if` above stopped this one being
        // single-expression — so the screenshot lane, and only the screenshot
        // lane, failed to compile with "missing return".
        return await store.accountStates().map { item in
            AccountsPane.AccountRow(
                id: item.account.id,
                handle: item.account.handle,
                provider: item.account.provider,
                displayName: item.account.displayName,
                state: item.state
            )
        }
    }

    // MARK: - An account list this build cannot open

    /// The same answer, published, because the limits window needs it while it
    /// is drawing rather than at the end of an `await`.
    ///
    /// Nothing is read from the keychain to keep this current. `load()` asked
    /// once at launch, with the keychain's own question turned off, and the
    /// store has been holding the answer since — so a poll can copy it out for
    /// the price of an actor hop.
    ///
    /// It is also the whole of knowing whether there is anything to offer a
    /// repair for. An item that was never written answers `errSecItemNotFound`,
    /// which is not a failure to read and leaves this `nil`; somebody who
    /// installed the app a minute ago cannot reach the sentence about accounts
    /// surviving an update, because as far as the keychain is concerned they
    /// have none to survive it.
    @Published private(set) var savedAccountsProblem: UnreadableAccountList?

    /// How many keychain dialogs this app has deliberately asked for.
    ///
    /// The keychain's question is a system dialog, and a `.transient` popover
    /// closes itself as soon as the focus moves — so the window that offers the
    /// repair is the window the repair takes off the screen, leaving a password
    /// prompt with nothing beside it to say what asked for one.
    ///
    /// A count rather than a flag, for the reason written above
    /// `appearancePreviewRequests`, and read by `StatusItemController`, which
    /// owns the window. Both facts travel this way for the same reason: the
    /// screens are handed no way to reach the status item.
    @Published private(set) var keychainDialogRequests = 0

    /// Why the saved accounts could not be read, or `nil` when they were.
    ///
    /// Shaped like `accountRows()` above and for the same two reasons: a
    /// screenshot build must not reach the keychain at all, and in demo there
    /// may be nothing there to reach — a repair offered against sample accounts
    /// would be a repair of nothing.
    func accountsProblem() async -> UnreadableAccountList? {
        #if SCREENSHOTS
        if isScreenshotRun { return nil }
        #endif
        if isDemo { return nil }
        return await store.whyUnreadable()
    }

    /// Re-reads the reason without polling.
    ///
    /// For the two moments a poll is the wrong instrument: a screen appearing,
    /// and a repair that failed. Both want the reason as it stands now, and a
    /// poll would fetch two services over the network to deliver a fact the
    /// store has been holding since launch.
    func refreshSavedAccountsProblem() async {
        savedAccountsProblem = await accountsProblem()
    }

    /// Puts the keychain's own question on screen, and takes the accounts back
    /// if it is answered yes.
    ///
    /// Nothing is lost on a refusal: the list stays shut, the guard stays up,
    /// and the button can be pressed again. The refusal is written down for the
    /// same reason the failure to read it was — the screen has one sentence to
    /// spend, and the status code belongs where somebody can read it later.
    ///
    /// The window is held open for the length of it, and the app is brought
    /// forward so the dialog arrives in front of whatever was there. Both are
    /// wanted by only one of the two callers — the settings screen is already
    /// frontmost and has no popover to lose — and both are harmless to the
    /// other, which is why they are here rather than in the window: the one
    /// place that raises this dialog is the one place that has to survive it.
    ///
    /// Released in `defer`. A refused dialog throws, and a count let go only on
    /// the way out would leave a popover pinned open for the rest of the
    /// session with nothing left that could unpin it.
    func openSavedAccounts() async throws {
        do {
            // Raised around the dialog and around nothing else.
            //
            // The `defer` used to sit in the function's own scope, which put
            // the poll below inside it — and a poll that never returns never
            // reaches the end of a scope. This file documents that happening
            // and `RefreshGate` exists because of it. The window pinned for a
            // dialog answered minutes ago would then stay pinned for the rest
            // of the session, with nothing left that could unpin it: both other
            // paths that restore `.transient` turn on `isPreviewing`. That is
            // the exact outcome the release exists to prevent, reached through
            // the release itself.
            keychainDialogRequests += 1
            defer { keychainDialogRequests -= 1 }
            try await store.openWithPermission()
        } catch {
            Self.log.error("saved accounts did not open: \(String(describing: error), privacy: .public)")
            // A failed attempt can still have moved: the item opened, and what
            // came out could not be understood. The reason is re-read before
            // the throw so the screens see the new one — they decide what to
            // say about the press by comparing the reason before with the
            // reason after, and a stale copy makes a changed situation read as
            // a press that did nothing.
            await refreshSavedAccountsProblem()
            throw error
        }
        // Before the poll, and not only through it. `refresh()` is gated: a
        // poll already in flight turns it into a request for another pass and
        // returns at once, leaving the window drawing a refusal that has just
        // been lifted — under a spinner that has stopped. The reason is the one
        // fact here that needs no network, so it is taken back immediately and
        // the readings follow when they follow.
        await refreshSavedAccountsProblem()
        await refresh()
    }

    /// Throws the unreadable item away. Destructive, and the screen that calls
    /// it says so before it does.
    func startAccountsOver() async throws {
        do {
            try await store.startOver()
        } catch {
            Self.log.error("starting over failed: \(String(describing: error), privacy: .public)")
            throw error
        }
        await refresh()
    }

    func forgetAccount(id: String) async throws {
        try await store.forget(id: id)
        await identities.forget(id)
        // `.timer`: the person asked to forget an account, not to be asked for
        // permission to read one.
        await refresh()
    }

    func forgetAllAccounts() async {
        for ref in await store.knownRefs() {
            try? await store.forget(id: ref.id)
        }
        await refresh()
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

    /// Writes the reading twice, to two different places, for two different
    /// readers.
    ///
    /// The app's own copy always: the threshold tracker restores its baseline
    /// from it at the next launch, and the statistics screen draws the history
    /// beside it. That copy lives in the app's own directory and needs nobody's
    /// permission.
    ///
    /// The shared copy only while a widget is on screen to read it. A widget is
    /// a separate process, so the only way to hand it data is the app group
    /// container — and macOS guards a group container as "data from other apps"
    /// unless the signature proves the app belongs to the team the group is
    /// filed under, which an ad-hoc signature cannot. Writing it unconditionally
    /// meant that prompt arrived on first launch, and again after every update,
    /// for everybody — including the majority who have no widget and would never
    /// have read what the write produced. Asked for when the widget exists, it
    /// lands next to the thing it is for.
    private func publishToWidget(_ accounts: [AccountSnapshot]) {
        let snapshot = SharedSnapshot(
            accounts: accounts,
            capturedAt: lastUpdated ?? Date(),
            rowLayout: preferences.rowLayout,
            showSnapshotAge: preferences.showSnapshotAge,
            languageCode: preferences.languageCode,
            pollingEvery: preferences.backgroundInterval
        )
        SharedStore.writeLocal(snapshot)

        Task { @MainActor in
            guard await Self.aWidgetIsOnScreen() else { return }
            SharedStore.write(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Whether the person has actually placed a widget.
    ///
    /// `false` on failure rather than `true`: the question is asked to avoid
    /// touching the group container, and an unanswerable question is not a
    /// reason to touch it. A widget that exists will be answered for on the next
    /// poll.
    private static func aWidgetIsOnScreen() async -> Bool {
        await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                switch result {
                case .success(let widgets): continuation.resume(returning: !widgets.isEmpty)
                case .failure: continuation.resume(returning: false)
                }
            }
        }
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
