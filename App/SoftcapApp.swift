import SwiftUI
import AppKit
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
                .onChange(of: delegate.preferences.value, initial: true) { _, new in
                    delegate.model.preferences = new
                    delegate.updates.preferences = new
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

    private lazy var statusItem = StatusItemController(
        model: model, preferences: preferences, updates: updates)

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            await preferences.load()
            model.preferences = preferences.value
            updates.preferences = preferences.value
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
