import SwiftUI
import AppKit
import Combine
import ProviderKit
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
                .onChange(of: delegate.preferences.value.appearance, initial: true) { _, new in
                    applyAppearance(new)
                }
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

        Task {
            await preferences.load()
            updates.recordCheck = { [preferences] moment in
                preferences.update { $0.lastUpdateCheck = moment }
            }
            applyAppearance(preferences.value.appearance)
            statusItem.install()

            // The quiet check, now and once a day after. It opens nothing: at
            // most it changes the words on a menu item and in the settings
            // footer.
            updates.startChecking()
        }
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


extension Severity {
    /// Bar and label colour. The thresholds live in `Severity`.
    var tint: Color {
        switch self {
        case .ok:       .green
        case .warning:  .yellow
        case .hot:      .orange
        case .critical: .red
        }
    }
}


/// Lets a SwiftUI window be told apart from the menu bar window without relying
/// on the title, which the system localizes.
extension NSHostingController: NSHostingViewProtocol {}
