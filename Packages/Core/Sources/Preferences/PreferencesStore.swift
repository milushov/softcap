import Foundation

/// Storage behind a protocol so tests never write to the real `UserDefaults`
/// and leave no trace in the system.
public protocol PreferencesStorage: Sendable {
    func read() async -> Data?
    func write(_ data: Data) async
}

public struct UserDefaultsStorage: PreferencesStorage {
    public static let key = "preferences"

    /// Apple documents `UserDefaults` as thread-safe but does not mark it
    /// `Sendable`. We mark it ourselves: otherwise it cannot live in a
    /// `Sendable` struct.
    nonisolated(unsafe) private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func read() -> Data? { defaults.data(forKey: Self.key) }
    public func write(_ data: Data) { defaults.set(data, forKey: Self.key) }
}

public actor PreferencesStore {
    private let storage: any PreferencesStorage
    private var value: Preferences = .defaults

    public init(storage: any PreferencesStorage) { self.storage = storage }

    /// Reads the settings. Any failure — corrupt data, a field set from another
    /// version — yields the defaults: settings are not a good reason for the app
    /// to refuse to start.
    @discardableResult
    public func load() async -> Preferences {
        guard let data = await storage.read(),
              let decoded = try? JSONDecoder().decode(Preferences.self, from: data)
        else {
            value = .defaults
            return value
        }
        value = decoded.normalized()
        return value
    }

    public func save(_ newValue: Preferences) async {
        value = newValue.normalized()
        guard let data = try? JSONEncoder().encode(value) else { return }
        await storage.write(data)
    }

    /// The last value read, without touching storage.
    public func current() -> Preferences { value }
}
