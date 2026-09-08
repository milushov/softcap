import AppKit

/// Opening the settings window.
///
/// The app is marked `LSUIElement`: it runs as an agent, without a Dock icon,
/// and never comes to the front on its own. The window does get created, but it
/// stays behind other applications' windows — which looks as if the menu item
/// were broken. Hence the explicit activation and the extra ordering to front.
@MainActor
enum SettingsWindow {
    static func open() {
        showInSwitcher()
        NSApp.activate(ignoringOtherApps: true)

        if let window = existing() {
            present(window)
            return
        }
        guard invokeMenuItem() else { giveUp(); return }
        waitForWindow(attemptsLeft: 30)
    }

    /// Waits for the window the menu item is building, looking every 50 ms for
    /// about a second and a half.
    ///
    /// A single short wait is not enough. How long the window takes is not ours
    /// to know — the first open builds the whole settings tree and loads the
    /// preferences — and a wait that fires too early is worse than a slow one:
    /// it puts the app back to agent mode while the window is still on its way,
    /// so the window arrives outside ⌘⇥, unfocused, and with nothing watching
    /// for its close.
    ///
    /// This also covers a menu item that was found but did nothing:
    /// `performActionForItem(at:)` is silent for a disabled item, and the
    /// attempts then run out and end in `giveUp()` rather than in a Dock icon
    /// with no window behind it.
    private static func waitForWindow(attemptsLeft: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let window = existing() {
                present(window)
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            guard attemptsLeft > 1 else { giveUp(); return }
            waitForWindow(attemptsLeft: attemptsLeft - 1)
        }
    }

    /// No window came. Going back to agent mode matters more than the beep: a
    /// Dock icon with nothing behind it is the worse leftover.
    private static func giveUp() {
        hideFromSwitcher()
        NSSound.beep()
    }

    private static func present(_ window: NSWindow) {
        // The window can be minimised now that the app is a regular one, and a
        // minimised window is not brought back by `makeKeyAndOrderFront` alone.
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        watchForClose(window)
    }

    /// Finds the settings item in the main menu and performs it.
    ///
    /// It is looked up by its **key equivalent** ⌘, not by title. The title
    /// comes from the system localisation: "Réglages…", "设置…", "الإعدادات…".
    /// Matching on text worked for two languages out of ten; in the rest the
    /// settings would not open at all.
    ///
    /// Every top-level submenu is searched, not just the one expected to hold
    /// the item. `NSApp.mainMenu` starts with the application menu — the Apple
    /// menu belongs to the system and is not part of it — and an index guessed
    /// wrong lands in "Edit", where there is no ⌘, and the settings stayed
    /// shut.
    private static func invokeMenuItem() -> Bool {
        guard let mainMenu = NSApp.mainMenu else { return false }

        for item in mainMenu.items {
            guard let submenu = item.submenu else { continue }
            guard let index = submenu.items.firstIndex(where: {
                $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == .command
            }) else { continue }

            submenu.performActionForItem(at: index)
            return true
        }

        return false
    }

    /// The settings window among the app's windows.
    ///
    /// Recognised by the type of its content, not by its title: the title is
    /// localised by the system too. The menu bar window is not an `NSWindow`
    /// with a standard frame, so it does not match.
    private static func existing() -> NSWindow? {
        NSApp.windows.first { window in
            window.styleMask.contains(.titled)
                && window.isVisible
                && window.contentViewController is NSHostingViewProtocol
        } ?? NSApp.windows.first { $0.styleMask.contains(.titled) && $0.canBecomeKey }
    }

    // MARK: - Presence in the ⌘⇥ switcher

    private static var closeObserver: NSObjectProtocol?

    /// The ⌘⇥ switcher lists regular applications only, so an agent is missing
    /// from it — and so is its window. Once the settings window lost focus
    /// there was no way back to it except through the menu bar icon.
    ///
    /// While the window is open the app becomes a regular one. A Dock icon
    /// comes along with it: `NSApplication` has a single activation policy for
    /// both, the switcher and the Dock cannot be asked for separately.
    private static func showInSwitcher() {
        NSApp.setActivationPolicy(.regular)
    }

    /// Back to agent mode once the last window is gone: a Dock icon for an app
    /// with nothing to show would only take up space.
    private static func hideFromSwitcher() {
        NSApp.setActivationPolicy(.accessory)
    }

    private static func watchForClose(_ window: NSWindow) {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }

        let closing = ObjectIdentifier(window)
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            Task { @MainActor in
                if !hasVisibleWindow(besides: closing) { hideFromSwitcher() }
            }
        }
    }

    /// Any window the user can see and switch to, other than the one closing
    /// right now. The menu bar item and the popover are not `.titled`, so they
    /// do not hold the app in the switcher.
    ///
    /// The closing window is excluded by identity rather than by waiting for it
    /// to disappear: `willClose` arrives while it is still on screen, and
    /// whether it is gone by the next pass of the loop is a matter of timing.
    private static func hasVisibleWindow(besides closing: ObjectIdentifier) -> Bool {
        NSApp.windows.contains {
            ObjectIdentifier($0) != closing
                && $0.styleMask.contains(.titled)
                && $0.isVisible
        }
    }
}

/// Marker for windows whose content is built with SwiftUI.
/// `NSHostingController` is a generic type, so it cannot be checked with `is`
/// without naming its parameter; the protocol solves that.
protocol NSHostingViewProtocol {}
