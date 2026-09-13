import SwiftUI
import AppKit
import Combine
import ProviderKit
import ClaudeProvider
import Diagnostics
import Monitoring
import Preferences
import StatusUI

@main
struct SoftcapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            SettingsView(model: delegate.preferences, appModel: delegate.model,
                         updates: delegate.updates)
        }
    }
}

/// The menu bar item lives in the delegate rather than a `MenuBarExtra` scene:
/// that is the only way to attach a context menu to the right click.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let model = AppModel()
    // A screenshot run keeps its settings in memory: see `ScreenshotFixtures`.
    #if SCREENSHOTS
    let preferences = PreferencesModel(
        store: PreferencesStore(storage: ScreenshotFixtures.Storage()))
    #else
    let preferences = PreferencesModel()
    #endif
    let updates = UpdateModel()

    private var cancellables: Set<AnyCancellable> = []

    private lazy var statusItem = StatusItemController(
        model: model, preferences: preferences, updates: updates)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Settings reach the rest of the app from here, and this is the third
        // time that lesson has been learned in this file.
        //
        // It used to be an `.onChange` on the settings scene. A scene's content
        // is built when its window opens and not again: the `App` observes this
        // delegate, which publishes nothing, so the modifier went on comparing
        // the value it had been built with. A setting therefore reached the
        // window when the settings window was next opened — or at the next
        // launch — which is the same shape `applyTheme` describes for the
        // appearance and `applyLanguage` for the language.
        //
        // The new setting is where it showed: turning on the minimal window
        // left the full one on screen. `Row layout`, `Order`, `Show snapshot
        // age` and both polling intervals had the same defect and nobody had
        // looked.
        //
        // A subscription instead. This delegate owns all three objects, so
        // wiring them to one another is its work and nobody else's.
        preferences.$value
            .sink { [model, updates] value in
                model.preferences = value
                updates.preferences = value
            }
            .store(in: &cancellables)

        model.login.didAddAccount = { [weak model, preferences] ref in
            // Sign-in can finish with settings closed or on another pane.
            // Reveal the account before polling, without relying on a view's
            // onChange subscription to have existed when success arrived.
            preferences.update {
                $0.hiddenAccounts.remove(ref.id)
                $0.disabledProviders.remove(ref.provider)
            }
            guard let model else { return }
            model.settingsSection = .accounts
            SettingsWindow.open()
            Task { await model.refreshAfterSignIn(ref) }
        }

        Task {
            startReporting()
            await preferences.load()
            updates.recordCheck = { [preferences] moment in
                preferences.update { $0.lastUpdateCheck = moment }
            }
            statusItem.install()

            // The quiet check, now and once a day after. It opens nothing: at
            // most it changes the words on a menu item and in the settings
            // footer.
            //
            // Not in the App Store build: there updates arrive through
            // TestFlight and the store, and a binary that replaces itself
            // would fail review — and could not swap a sandboxed bundle anyway.
            #if !APPSTORE
            updates.startChecking()
            #endif

            #if SCREENSHOTS
            stageScreenshot()
            #endif
        }
    }

    #if SCREENSHOTS
    /// Opens whatever `SOFTCAP_SHOT` names, so each screenshot is one launch
    /// with one thing on screen and nothing to click.
    ///
    /// The window shape — full or minimal — is not staged here: it is a setting,
    /// and `ScreenshotFixtures.Storage` reads `SOFTCAP_SHOT_MINIMAL` for it.
    private func stageScreenshot() {
        let wanted = ProcessInfo.processInfo.environment["SOFTCAP_SHOT"] ?? "window"
        NSApp.activate(ignoringOtherApps: true)

        // Asked of the enum rather than a list written out beside it. The list
        // was a copy of the raw values and went stale the moment a ninth screen
        // arrived: `SOFTCAP_SHOT=contribute` fell through to the else branch and
        // quietly photographed the menu bar window instead of the new screen.
        if let section = SettingsSection(rawValue: wanted) {
            model.settingsSection = section
            SettingsWindow.open()
        } else {
            statusItem.showPopoverForScreenshot()
        }

        // Whatever holds the keyboard draws a focus ring, and in the sidebar
        // that is a second highlighted row beside the selected one — which in a
        // screenshot reads as the screen not knowing which section it is on.
        // After the window has opened, because that is what takes the focus.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            for window in NSApp.windows { window.makeFirstResponder(nil) }
        }
    }
    #endif

    /// Arranges for a failure to be describable, before anything can fail.
    ///
    /// Not compiled into a debug build at all. A flag would have been one line
    /// shorter and would have left a real reporter sitting behind it, one
    /// `setEnabled(true)` away from posting the author's own development
    /// failures to the collector; with no reporter to enable, the shared
    /// instance is inert no matter what the setting says.
    ///
    /// It runs before the settings are loaded, so it starts switched off and
    /// `PreferencesModel` turns it on a moment later if that is what the setting
    /// says. The other order would report for one moment on a machine whose
    /// owner had turned reporting off.
    private func startReporting() {
        #if !DEBUG
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            ?? "unknown"
        // The two lanes carry the same version number and are not the same
        // program: the App Store build is sandboxed, has no updater, and reaches
        // less of the machine. A report saying only "0.1.4" is unattributable to
        // either — so the lane goes in `environment`, which is the axis for one
        // codebase delivered two ways, and not in `release`, which is the unit
        // release health and "fixed in the next version" are counted in. Two
        // release series would make one regression read as two unrelated ones.
        #if APPSTORE
        let lane = "appstore"
        #else
        let lane = "production"
        #endif
        Task {
            await Diagnostics.shared.start(
                reporter: CollectorReporter(
                    http: URLSessionHTTPClient(),
                    destination: Diagnostics.shipped,
                    client: "softcap/\(version)"
                ),
                release: "softcap@\(version)",
                environment: lane,
                enabled: false
            )
        }
        #endif
    }
}

/// Turns the user's choice into an AppKit appearance.
/// `nil` means "follow the system", which is also the default.
@MainActor
func applyAppearance(_ appearance: Appearance) {
    NSApp.appearance = switch appearance {
    case .system: nil
    case .light:  NSAppearance(named: .aqua)
    case .dark:   NSAppearance(named: .darkAqua)
    }
}


/// Lets a SwiftUI window be told apart from the menu bar window without relying
/// on the title, which the system localizes.
extension NSHostingController: NSHostingViewProtocol {}
