import AppKit
import SwiftUI
import Combine
import ProviderKit
import Preferences
import Monitoring
import StatusUI

/// The menu bar item and everything around it.
///
/// A custom `NSStatusItem` rather than `MenuBarExtra`: the latter offers no way
/// to configure the right click, and a context menu is expected behaviour for
/// menu bar apps. A side benefit is that the system button combines icon and
/// label itself.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let preferences: PreferencesModel
    private let updates: UpdateModel
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables: Set<AnyCancellable> = []
    private var tick: Timer?
    private var appearanceObserver: NSKeyValueObservation?

    /// Whether the window on screen is the one the Appearance screen asked for.
    private var isPreviewing = false

    /// Whether somebody put the preview away by hand.
    ///
    /// Clicking the status item, or right-clicking it for the menu, closes the
    /// window; without remembering that, the pass below would read the screen
    /// still asking for it and open it straight back, and switching apps and
    /// returning would open a window that had been deliberately dismissed.
    /// Cleared when the Appearance screen asks again.
    private var previewDismissedByHand = false

    init(model: AppModel, preferences: PreferencesModel, updates: UpdateModel) {
        self.model = model
        self.preferences = preferences
        self.updates = updates
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let glyph = MenuBarGlyph.image()
        glyph.accessibilityDescription = Localization.shared("Subscription limits")
        item.button?.image = glyph
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(buttonClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        // The window does not follow `NSApp.appearance` on its own.
        //
        // It is an `NSPopover` hanging off the status item's button, and a status
        // item's window belongs to the system menu bar rather than to this app —
        // so the popover inherits the menu bar's appearance and stayed light
        // while every window the app owns had gone dark. Setting it explicitly is
        // the only way.
        //
        // Observed rather than set once, because the setting can be changed while
        // the window is open — which is precisely what happens: the settings
        // screen is where the switch lives, and both can be on screen together.
        // `[weak self]` on the outer closure, not the inner one: the observation is
        // stored on `self`, so a strong capture here would be a cycle.
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) {
            [weak self] app, _ in
            // KVO calls back on whichever thread changed the value; appearance is
            // only ever set from the main one, and the compiler cannot know that.
            MainActor.assumeIsolated {
                self?.popover?.appearance = app.effectiveAppearance
            }
        }

        // Everything that can change whether the window should be out goes to
        // one place, and that place reads the answer when it runs rather than
        // carrying one decided earlier.
        //
        // Three separate hops used to act on a value captured at emission. Hops
        // onto the main actor are not ordered against each other, so two sidebar
        // clicks — away from Appearance and back — could run the close after the
        // open and leave no window with nothing left to ask for one. A pass that
        // re-reads cannot end that way round whichever order it runs in.
        //
        // Deferred rather than acted on inside the sink because the count is
        // raised from `onAppear`, and showing a window in the middle of a
        // SwiftUI update is how a redraw lands inside a redraw.
        //
        // The app being in front is part of the answer: a window told not to
        // close itself would otherwise go on floating over whatever the person
        // switched to. It comes back when they return, because the screen that
        // asked for it is still open.
        let previewSignals = Publishers.Merge3(
            model.$appearancePreviewRequests.map { _ in () },
            NotificationCenter.default
                .publisher(for: NSApplication.didResignActiveNotification).map { _ in () },
            NotificationCenter.default
                .publisher(for: NSApplication.didBecomeActiveNotification).map { _ in () }
        )
        previewSignals
            .sink { [weak self] in
                Task { @MainActor [weak self] in self?.syncAppearancePreview() }
            }
            .store(in: &cancellables)

        // Asking again clears a dismissal: leaving the screen and coming back is
        // how somebody says they would like the window after all.
        model.$appearancePreviewRequests
            .map { $0 > 0 }
            .removeDuplicates()
            .sink { [weak self] wanted in
                if wanted { self?.previewDismissedByHand = false }
            }
            .store(in: &cancellables)

        // A keychain dialog this app asked for holds the window open for as
        // long as it stands. Without it the window that offers the repair is
        // the window the repair takes off the screen: a `.transient` popover
        // closes itself the moment focus moves, and a system dialog moving the
        // focus is the whole of what the button does.
        model.$keychainDialogRequests
            .map { $0 > 0 }
            .removeDuplicates()
            .sink { [weak self] asking in
                Task { @MainActor [weak self] in self?.holdWindowOpen(asking) }
            }
            .store(in: &cancellables)

        // The label beside the icon is recomputed on every data update and
        // whenever the "In the menu bar" setting changes.
        model.$summary
            .combineLatest(preferences.$value)
            .sink { [weak self] summary, prefs in
                self?.updateTitle(summary: summary, content: prefs.menuBarContent)
            }
            .store(in: &cancellables)

        // The remainder is recomputed every second: it is derived from the
        // current moment, and without a tick the label would sit unchanged
        // between polls — up to five minutes in the background — then jump.
        let tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.updateTitle(
                    summary: self.model.summary,
                    content: self.preferences.value.menuBarContent
                )
            }
        }
        RunLoop.main.add(tick, forMode: .common)
        self.tick = tick

        // The shortcut that opens the window is registered here, where the
        // popover and the button live, and re-registered whenever it changes.
        //
        // `Preferences` has carried `openWindowHotKey` and `HotKeyID.openWindow`
        // since the settings screen was built, the plan specified a row for it,
        // and nothing ever registered it: the field was stored, the identifier
        // was declared, and pressing the combination did nothing because no
        // combination could be recorded and nothing would have listened.
        //
        // It goes here rather than in `AppModel` for the reason written there:
        // registration in a lazily-created object does nothing until that object
        // exists. This controller is installed at launch.
        preferences.$value
            .map(\.openWindowHotKey)
            .removeDuplicates()
            .sink { [weak self] combo in
                HotKeyCenter.shared.register(combo, id: HotKeyID.openWindow) {
                    Task { @MainActor [weak self] in self?.openFromHotKey() }
                }
            }
            .store(in: &cancellables)

        Task { await model.start() }
    }

    /// Opens the window from the keyboard.
    ///
    /// The same toggle the button uses, so pressing it twice closes what it
    /// opened. Anchored to the status item because a popover has to hang off
    /// something, and that is where this one belongs.
    private func openFromHotKey() {
        guard let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        togglePopover(from: button)
    }

    private func updateTitle(summary: MenuBarSummary?, content: MenuBarContent) {
        guard let button = statusItem?.button else { return }
        guard let summary else {
            button.attributedTitle = NSAttributedString()
            button.setAccessibilityLabel(Localization.shared("Subscription limits"))
            return
        }

        // Spoken separately from the label: the label is an abbreviation tuned
        // for width, and abbreviations read badly.
        button.setAccessibilityLabel(Localization.shared.spokenMenuBar(
            percent: summary.percent, remaining: summary.remaining,
            // Resolved from the list rather than carried as a name: the
            // summary holds an identifier, and the sentence wants the service,
            // the address and the plan, which only the row has. Nil whenever
            // the figure is about the whole list, and the word comes back.
            account: summary.accountID.flatMap { id in
                model.snapshots.first { $0.id == id }
            }))

        let percent = Localization.shared.percent(summary.percent)
        let timer = Localization.shared.remainingCompact(summary.remaining)

        let text: String? = switch content {
        case .iconOnly: nil
        case .percent:  percent
        case .timer:    timer
        case .both:     "\(percent) · \(timer)"
        }
        guard let text else { button.attributedTitle = NSAttributedString(); return }


        // The space separates label from icon: `imagePosition` gives no gap.
        button.attributedTitle = NSAttributedString(string: " \(text)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular),
            // A line box includes room for descenders, and digits have none —
            // so centring puts the label above the icon. Measured from a menu
            // bar screenshot: 2.5 retina pixels, i.e. 1.25 pt. A negative
            // offset lowers the text relative to the baseline.
            .baselineOffset: -1.25,
        ])
    }

    // MARK: - clicks

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        let rightClick = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true

        if rightClick {
            showMenu(from: sender)
        } else {
            togglePopover(from: sender)
        }
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if let popover, popover.isShown {
            // Closing by hand outranks a screen that is still asking, until it
            // asks again. Otherwise the pass that reconciles the two would put
            // back what was just pushed away.
            if isPreviewing { previewDismissedByHand = true }
            popover.performClose(nil)
            return
        }

        let popover = self.popover ?? makePopover()
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        // Without activation the window appears but the keyboard stays with
        // whatever app was frontmost.
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: - the window beside the settings screen

    /// Brings the window out while the Appearance screen is open, or puts it
    /// away — whichever the moment calls for.
    ///
    /// One pass, run after anything that could change the answer, reading the
    /// answer now. Every caller that decided for itself had to be right about an
    /// ordering the language does not promise.
    ///
    /// `.applicationDefined` is what makes the preview possible at all. A
    /// `.transient` popover closes itself as soon as the focus moves, and moving
    /// the focus is exactly what clicking a control in settings does — so the
    /// window a person is trying to watch would vanish at the first thing they
    /// changed.
    func syncAppearancePreview() {
        // A screenshot run stages its own window; a second one arriving
        // uninvited would be photographed with the Appearance screen.
        #if SCREENSHOTS
        return
        #else
        let wanted = model.appearancePreviewRequests > 0
            && !previewDismissedByHand
            && NSApp.isActive
        wanted ? showAppearancePreview() : dropAppearancePreview()
        #endif
    }

    /// The keyboard stays where it is. `togglePopover` makes the popover's window
    /// key because somebody opening it means to use it; here they mean to use
    /// settings, and taking the keyboard away would leave the controls they are
    /// working in unable to answer.
    private func showAppearancePreview() {
        guard !isPreviewing else { return }
        // Not just that the button exists: `show(relativeTo:of:)` raises
        // `NSInvalidArgumentException` for a view that is in no window, and a
        // status item has no window when there is no room for it in a crowded
        // menu bar. Clicking it was impossible in that state, so nothing used to
        // reach this call; opening a settings screen reaches it without a click.
        // `showPopoverForScreenshot` guards the same thing for the same reason.
        guard let button = statusItem?.button, button.window != nil else { return }

        let popover = self.popover ?? makePopover()
        self.popover = popover

        // Only a window this brought out is pinned. Adopting one the person
        // opened themselves would take away its own judgement about closing and
        // leave it hanging over another app with nobody who means to close it —
        // and a window part-way through closing still reports itself shown, so
        // adopting that one pinned something already on its way out. When the
        // close finishes, `popoverDidClose` asks for this pass again.
        guard !popover.isShown else { return }

        isPreviewing = true
        popover.behavior = .applicationDefined
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
    }

    /// Stops the window closing itself while a dialog this app asked for is
    /// standing in front of it.
    ///
    /// The release is not conditional on the window being open. A popover is
    /// kept and reused, so a behaviour left on one that closed in the meantime
    /// is a behaviour the next ordinary click inherits — a window that no longer
    /// puts itself away, for a dialog that finished minutes ago.
    ///
    /// It does yield to the appearance preview, which pins the same window for
    /// its own reasons and has its own release. Taking the pin away here would
    /// close a window the Appearance screen is still showing.
    private func holdWindowOpen(_ asking: Bool) {
        guard let popover else { return }
        if asking {
            popover.behavior = .applicationDefined
        } else if !isPreviewing {
            popover.behavior = .transient
        }
    }

    /// Puts away only what the preview brought out, and gives the window back
    /// its own judgement about when to close.
    private func dropAppearancePreview() {
        guard isPreviewing else { return }
        isPreviewing = false
        popover?.behavior = .transient
        popover?.performClose(nil)
    }

    #if SCREENSHOTS
    /// Held only so the window below is not released the moment it is shown.
    private var screenshotWindow: NSWindow?

    /// Opens the window without a click.
    ///
    /// A screenshot run would otherwise have to find the status item on screen
    /// and press it through the accessibility API — which needs a permission
    /// granted to whichever terminal happens to be running the tool, and fails
    /// silently when it is not there.
    ///
    /// Two ways, because the first one is not dependable while the author's own
    /// copy is running: a status item is hosted by Control Centre, a second
    /// copy's item can be placed where there is no room for it, and a
    /// `.transient` popover closes itself the moment focus moves — which
    /// activating this process does. So the popover is asked first, with its
    /// self-closing turned off, and if it does not appear the same view is shown
    /// in a window of its own.
    func showPopoverForScreenshot() {
        if let button = statusItem?.button, button.window != nil {
            let popover = self.popover ?? makePopover()
            self.popover = popover
            popover.behavior = .applicationDefined
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
            if popover.isShown { return }
        }
        showTheWindowOnItsOwn()
    }

    /// The same SwiftUI view the popover carries, in a plain window: no title
    /// bar, no buttons, the system's own rounded corners and shadow. What is
    /// lost against the real popover is the arrow pointing at the menu bar,
    /// which a store screenshot has no room to explain anyway.
    private func showTheWindowOnItsOwn() {
        let host = NSHostingController(rootView: PopoverView(model: model))
        // Without this the view is inset by the height of the title bar that is
        // not being drawn, and the window opens with a band of empty background
        // above its first row — which the real popover does not have.
        host.safeAreaRegions = []

        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.appearance = NSApp.effectiveAppearance
        window.center()
        window.makeKeyAndOrderFront(nil)
        screenshotWindow = window
    }
    #endif

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        // The observer above only fires on a change; a popover built after the
        // last one would otherwise open in the menu bar's appearance.
        popover.appearance = NSApp.effectiveAppearance
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(model: model)
        )
        return popover
    }

    /// The right-click context menu — the same actions as the window footer.
    private func showMenu(from button: NSStatusBarButton) {
        // The same as closing it by hand: a right click is how somebody reaches
        // settings from here, and the window should not reappear behind the menu.
        if isPreviewing { previewDismissedByHand = true }
        popover?.performClose(nil)

        let menu = NSMenu()

        // The version, as a heading rather than an action. The app has no Dock
        // icon and no menu bar of its own, so this is the only place it can say
        // which build it is. Disabled on purpose: a menu item that looks
        // clickable and is not is worse than one that plainly is not.
        let version = NSMenuItem(
            title: String(format: Localization.shared("Softcap %@"), updates.versionText),
            action: nil, keyEquivalent: ""
        )
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(.separator())

        let refresh = NSMenuItem(
            title: Localization.shared("Refresh"), action: #selector(refreshNow), keyEquivalent: "r"
        )
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: Localization.shared("Settings…"), action: #selector(openSettings), keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        let addAccount = NSMenuItem(
            title: Localization.shared("Add account…"),
            action: nil, keyEquivalent: ""
        )
        let providers = NSMenu()
        for provider in LoginController.providers {
            let item = NSMenuItem(
                title: provider.productName,
                action: #selector(addAccount(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = provider.rawValue
            item.isEnabled = !model.login.isRunning
            providers.addItem(item)
        }
        providers.autoenablesItems = false
        addAccount.submenu = providers
        menu.addItem(addAccount)

        let statistics = NSMenuItem(
            title: Localization.shared("Statistics") + "…",
            action: #selector(openStatistics), keyEquivalent: ""
        )
        statistics.target = self
        menu.addItem(statistics)

        menu.addItem(.separator())

        // The one setting with a home outside settings. It is the whole shape
        // of the window rather than a detail of it, and a checked item says
        // which shape is on without being asked.
        let minimal = NSMenuItem(
            title: Localization.shared("Minimal window"),
            action: #selector(toggleMinimalWindow), keyEquivalent: ""
        )
        minimal.target = self
        minimal.state = preferences.value.minimalWindow ? .on : .off
        menu.addItem(minimal)

        // Reads as an offer once there is one to make. This change, and the
        // same one in the settings footer, is the whole of how loudly a found
        // update announces itself — in both lanes: the store copy is told the
        // same way, and opens a screen that sends it to the store.
        let update = NSMenuItem(
            title: updates.availableVersion.map {
                String(format: Localization.shared("Update to %@"), $0.description)
            } ?? Localization.shared("Check for updates…"),
            action: #selector(openUpdates), keyEquivalent: ""
        )
        update.target = self
        menu.addItem(update)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: Localization.shared("Quit Softcap"), action: #selector(quit), keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        // Shown through statusItem rather than popUpMenu: otherwise the button
        // stays highlighted after the menu closes.
        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func refreshNow() {
        Task { await model.refresh() }
    }

    @objc private func openSettings() {
        SettingsWindow.open()
    }

    @objc private func openUpdates() {
        model.settingsSection = .updates
        SettingsWindow.open()
        // Asked for by hand, so it says "this is the latest version" rather
        // than going quiet the way the daily check does — but it does not throw
        // away a release already found, and a second press does not start a
        // second check.
        Task { await updates.checkUnlessSomethingIsAlreadyOffered(now: Date()) }
    }

    /// Opens the Accounts section and starts the browser sign-in.
    ///
    /// Both, not just the second: a sign-in can come back asking for a code
    /// pasted by hand, and the field that takes it is on that screen. One
    /// started with nothing on screen would strand whoever pressed it.
    @objc private func addAccount(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let provider = ProviderID(rawValue: raw) else { return }
        model.settingsSection = .accounts
        SettingsWindow.open()
        model.login.start(provider: provider)
    }

    @objc private func openStatistics() {
        model.settingsSection = .statistics
        SettingsWindow.open()
    }

    @objc private func toggleMinimalWindow() {
        preferences.update { $0.minimalWindow.toggle() }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        model.isPopoverOpen = false
        // However it closed, the preview is over. Without this the window would
        // keep the behaviour the preview gave it, and the next ordinary click
        // would open one that no longer closes by itself.
        if isPreviewing {
            isPreviewing = false
            popover?.behavior = .transient
        }
        // And now that the old window has finished leaving, ask again whether a
        // new one is wanted. This is what recovers the case where the screen
        // asked while a window was still closing: there was nothing to pin then,
        // and this is the moment there is.
        syncAppearancePreview()
    }

    func popoverDidShow(_ notification: Notification) {
        model.isPopoverOpen = true
    }
}
