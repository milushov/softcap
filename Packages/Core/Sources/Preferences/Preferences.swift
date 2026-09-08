import Foundation
import ProviderKit

public enum Appearance: String, Codable, Sendable, CaseIterable {
    case system, light, dark

}

public enum MenuBarContent: String, Codable, Sendable, CaseIterable {
    case iconOnly, timer, percent, both

}

public enum PrimaryWindow: String, Codable, Sendable, CaseIterable {
    case worst, session, weekly

}

public enum RowLayout: String, Codable, Sendable, CaseIterable {
    case twoWindows, compact, rings

}

public enum Ordering: String, Codable, Sendable, CaseIterable {
    case leastLoadedFirst, byName

}

public enum WindowScope: String, Codable, Sendable, CaseIterable {
    case session, weekly, both


    /// Whether a window with this identifier falls under the chosen scope.
    public func includes(windowID: String) -> Bool {
        switch self {
        case .both:    true
        case .session: windowID == "session"
        case .weekly:  windowID == "weekly"
        }
    }
}

/// A key combination, stored as Carbon key codes rather than characters: the
/// character depends on the keyboard layout, the key code does not, so the
/// shortcut does not wander when the input language changes.
public struct HotKeyCombo: Codable, Sendable, Hashable {
    public static let control: UInt32 = 1 << 12
    public static let option: UInt32 = 1 << 11
    public static let shift: UInt32 = 1 << 9
    public static let command: UInt32 = 1 << 8

    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// How the combination reads in the interface. Symbol order is the macOS one.
    public var displayString: String {
        var result = ""
        if modifiers & Self.control != 0 { result += "⌃" }
        if modifiers & Self.option != 0 { result += "⌥" }
        if modifiers & Self.shift != 0 { result += "⇧" }
        if modifiers & Self.command != 0 { result += "⌘" }
        return result + Self.name(for: keyCode)
    }

    private static let names: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M", 49: "Space",
    ]

    private static func name(for code: UInt32) -> String {
        names[code] ?? "#\(code)"
    }
}

public struct Preferences: Codable, Sendable, Equatable {
    // Appearance
    /// Interface language code; `nil` means "follow the system". Stored as a
    /// string rather than an enum: the list of languages lives in the interface
    /// layer, and the model should not change when a translation is added.
    public var languageCode: String?
    public var appearance: Appearance
    public var menuBarContent: MenuBarContent
    public var primaryWindow: PrimaryWindow
    public var rowLayout: RowLayout
    public var ordering: Ordering
    public var showSnapshotAge: Bool

    // Notifications
    public var notificationsEnabled: Bool
    public var thresholds: [Int]
    public var notifyOnRecovery: Bool
    public var notifyWindows: WindowScope
    public var quietHours: QuietHours?

    // Polling and launch
    public var foregroundInterval: TimeInterval
    public var backgroundInterval: TimeInterval
    public var refreshAfterWake: Bool
    public var openWindowHotKey: HotKeyCombo?
    public var refreshHotKey: HotKeyCombo?

    // Updates
    public var checksForUpdates: Bool
    /// When the app last asked GitHub. `nil` means it never has.
    public var lastUpdateCheck: Date?

    // Services and accounts
    public var disabledProviders: Set<ProviderID>
    public var hiddenAccounts: Set<String>
    public var codexRoot: String?

    /// Allowed polling bounds. More often than twice a minute is pointless:
    /// the service does not recompute limits instantly. Less often than hourly
    /// and the monitor stops being one.
    public static let intervalRange: ClosedRange<TimeInterval> = 30...3600

    public static let defaults = Preferences(
        languageCode: nil,
        appearance: .system,
        menuBarContent: .timer,
        primaryWindow: .worst,
        rowLayout: .twoWindows,
        ordering: .leastLoadedFirst,
        showSnapshotAge: true,
        notificationsEnabled: true,
        thresholds: [95, 80],
        notifyOnRecovery: true,
        notifyWindows: .both,
        quietHours: nil,
        foregroundInterval: 60,
        backgroundInterval: 300,
        refreshAfterWake: true,
        openWindowHotKey: nil,
        refreshHotKey: nil,
        checksForUpdates: true,
        lastUpdateCheck: nil,
        disabledProviders: [],
        hiddenAccounts: [],
        codexRoot: nil
    )

    /// Brings values into range. Called before saving and after reading:
    /// settings may arrive from a file someone edited by hand.
    public func normalized() -> Preferences {
        var copy = self
        copy.thresholds = Array(Set(thresholds.filter { $0 > 0 && $0 <= 100 }))
            .sorted(by: >)
        copy.foregroundInterval = Self.clamp(foregroundInterval)
        copy.backgroundInterval = Self.clamp(backgroundInterval)
        return copy
    }

    private static func clamp(_ value: TimeInterval) -> TimeInterval {
        min(max(value, intervalRange.lowerBound), intervalRange.upperBound)
    }
}

extension Preferences {
    /// Decoded field by field, each falling back to its default.
    ///
    /// The synthesised `Codable` refuses a blob that is missing any one of the
    /// sixteen non-optional fields, and `PreferencesStore.load()` answers a
    /// refusal with `.defaults` — so a single absent key silently discards the
    /// language, the appearance, the thresholds, the quiet hours, the hidden
    /// accounts, the hot keys and the Codex root, all at once. Adding a
    /// twenty-second setting would have done that to everyone who upgraded.
    ///
    /// A malformed value falls back the same way, for the same reason: one
    /// setting that will not parse is not a reason to lose the other twenty.
    /// `SharedSnapshot` learned this by making one field optional; this is the
    /// same lesson made general.
    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Preferences.defaults

        func read<T: Decodable>(_ key: CodingKeys, _ default: T) -> T {
            ((try? box.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? `default`
        }
        func readOptional<T: Decodable>(_ key: CodingKeys, _ default: T?) -> T? {
            guard box.contains(key) else { return `default` }
            return (try? box.decodeIfPresent(T.self, forKey: key)) ?? `default`
        }

        languageCode         = readOptional(.languageCode, fallback.languageCode)
        appearance           = read(.appearance, fallback.appearance)
        menuBarContent       = read(.menuBarContent, fallback.menuBarContent)
        primaryWindow        = read(.primaryWindow, fallback.primaryWindow)
        rowLayout            = read(.rowLayout, fallback.rowLayout)
        ordering             = read(.ordering, fallback.ordering)
        showSnapshotAge      = read(.showSnapshotAge, fallback.showSnapshotAge)
        notificationsEnabled = read(.notificationsEnabled, fallback.notificationsEnabled)
        thresholds           = read(.thresholds, fallback.thresholds)
        notifyOnRecovery     = read(.notifyOnRecovery, fallback.notifyOnRecovery)
        notifyWindows        = read(.notifyWindows, fallback.notifyWindows)
        quietHours           = readOptional(.quietHours, fallback.quietHours)
        foregroundInterval   = read(.foregroundInterval, fallback.foregroundInterval)
        backgroundInterval   = read(.backgroundInterval, fallback.backgroundInterval)
        refreshAfterWake     = read(.refreshAfterWake, fallback.refreshAfterWake)
        openWindowHotKey     = readOptional(.openWindowHotKey, fallback.openWindowHotKey)
        refreshHotKey        = readOptional(.refreshHotKey, fallback.refreshHotKey)
        checksForUpdates     = read(.checksForUpdates, fallback.checksForUpdates)
        lastUpdateCheck      = readOptional(.lastUpdateCheck, fallback.lastUpdateCheck)
        disabledProviders    = read(.disabledProviders, fallback.disabledProviders)
        hiddenAccounts       = read(.hiddenAccounts, fallback.hiddenAccounts)
        codexRoot            = readOptional(.codexRoot, fallback.codexRoot)
    }
}
