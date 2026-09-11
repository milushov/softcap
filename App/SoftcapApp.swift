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
    let preferences = PreferencesModel()
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
            updates.startChecking()
        }
    }

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
        Task {
            await Diagnostics.shared.start(
                reporter: CollectorReporter(
                    http: URLSessionHTTPClient(),
                    destination: Diagnostics.shipped,
                    client: "softcap/\(version)"
                ),
                release: "softcap@\(version)",
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
