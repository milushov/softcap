import Testing
import Foundation
@testable import Preferences

private actor MemoryStorage: PreferencesStorage {
    private var data: Data?
    init(_ seed: Data? = nil) { data = seed }
    func read() -> Data? { data }
    func write(_ value: Data) { data = value }
}

@Test func emptyStorageGivesDefaults() async {
    let store = PreferencesStore(storage: MemoryStorage())
    #expect(await store.load() == Preferences.defaults)
}

@Test func savedValueComesBack() async {
    let storage = MemoryStorage()
    let store = PreferencesStore(storage: storage)
    var p = Preferences.defaults
    p.appearance = .dark
    p.thresholds = [70]
    await store.save(p)

    let reopened = PreferencesStore(storage: storage)
    let loaded = await reopened.load()
    #expect(loaded.appearance == .dark)
    #expect(loaded.thresholds == [70])
}

@Test func saveNormalizesBeforeWriting() async {
    let storage = MemoryStorage()
    let store = PreferencesStore(storage: storage)
    var p = Preferences.defaults
    p.thresholds = [80, 95, 80]
    p.foregroundInterval = 1
    await store.save(p)

    let loaded = await PreferencesStore(storage: storage).load()
    #expect(loaded.thresholds == [95, 80])
    #expect(loaded.foregroundInterval == 30)
}

@Test func corruptedDataFallsBackToDefaults() async {
    let storage = MemoryStorage(Data("this is not json".utf8))
    let store = PreferencesStore(storage: storage)
    // A damaged file must not bring the app down.
    #expect(await store.load() == Preferences.defaults)
}

/// Settings written before a field existed, or by a version that has one more.
///
/// This used to expect every setting to be discarded, on the grounds that not
/// crashing mattered more. Both are available: what is there is kept and what is
/// missing takes its default, so adding a twenty-second setting no longer resets
/// the twenty-one somebody chose.
@Test func partialDataKeepsWhatItHas() async {
    let storage = MemoryStorage(Data(#"{"appearance":"dark"}"#.utf8))
    let loaded = await PreferencesStore(storage: storage).load()
    #expect(loaded.appearance == .dark, "the one setting that was there was thrown away")
    #expect(loaded.backgroundInterval == Preferences.defaults.backgroundInterval)
    #expect(loaded.thresholds == Preferences.defaults.thresholds)
}

/// One field of the wrong type is one field, not twenty-one.
@Test func aMalformedFieldDoesNotTakeTheRestWithIt() async {
    let storage = MemoryStorage(Data(#"{"appearance":"dark","thresholds":"lots"}"#.utf8))
    let loaded = await PreferencesStore(storage: storage).load()
    #expect(loaded.appearance == .dark)
    #expect(loaded.thresholds == Preferences.defaults.thresholds)
}

/// Every field, round-tripped, so the hand-written decoder cannot quietly drop
/// one. A `Preferences` unlike the defaults in every field it can differ in.
@Test func everySettingSurvivesTheTrip() async {
    var chosen = Preferences.defaults
    chosen.languageCode = "ru"
    chosen.appearance = .light
    chosen.menuBarContent = .percent
    chosen.primaryWindow = .weekly
    chosen.rowLayout = .rings
    chosen.ordering = .custom
    chosen.customAccountOrder = ["codex/example", "claude/x"]
    chosen.showSnapshotAge = false
    chosen.notificationsEnabled = false
    chosen.thresholds = [70, 40]
    chosen.notifyOnRecovery = false
    chosen.notifyWindows = .weekly
    chosen.foregroundInterval = 120
    chosen.backgroundInterval = 900
    chosen.refreshAfterWake = false
    chosen.disabledProviders = [.codex]
    chosen.hiddenAccounts = ["claude/x"]
    chosen.codexRoot = "/somewhere/else"

    let storage = MemoryStorage()
    let store = PreferencesStore(storage: storage)
    await store.save(chosen)
    let back = await PreferencesStore(storage: storage).load()
    #expect(back == chosen.normalized(), "a setting did not survive being written and read")
}

@Test func currentReturnsLastLoadedWithoutTouchingStorage() async {
    let store = PreferencesStore(storage: MemoryStorage())
    _ = await store.load()
    #expect(await store.current() == Preferences.defaults)
}

@Test func switchingToAutomaticOrderKeepsTheSavedArrangement() async {
    let storage = MemoryStorage()
    let store = PreferencesStore(storage: storage)
    var settings = Preferences.defaults
    settings.ordering = .custom
    settings.setCustomAccountOrder(["codex/example", "claude/example"])
    await store.save(settings)

    settings.ordering = .byName
    await store.save(settings)
    let reopened = await PreferencesStore(storage: storage).load()
    #expect(reopened.ordering == .byName)
    #expect(reopened.customAccountOrder == ["codex/example", "claude/example"])
}
