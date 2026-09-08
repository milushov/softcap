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
            percent: summary.percent, remaining: summary.remaining))

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

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(model: model)
        )
        return popover
    }

    /// The right-click context menu — the same actions as the window footer.
    private func showMenu(from button: NSStatusBarButton) {
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

        // Reads as an offer once there is one to make. This change, and the
        // same one in the settings footer, is the whole of how loudly a found
        // update announces itself.
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
        Task { await model.refresh(.person) }
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

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        model.isPopoverOpen = false
    }

    func popoverDidShow(_ notification: Notification) {
        model.isPopoverOpen = true
    }
}
