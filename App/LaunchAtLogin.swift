import Foundation
import ServiceManagement

/// Launch at login.
///
/// The state is read from the system rather than stored in settings: the user can
/// turn the login item off in System Settings, and a stored value would then lie.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
