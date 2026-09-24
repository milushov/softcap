import Testing
import Foundation
import ProviderKit
@testable import Preferences

@Test func defaultsMatchTheSpec() {
    let p = Preferences.defaults
    #expect(p.appearance == .system)
    #expect(p.menuBarContent == .timer)
    #expect(p.menuBarAccount == .inUse)
    #expect(p.primaryWindow == .worst)
    #expect(p.rowLayout == .twoWindows)
    #expect(p.ordering == .leastLoadedFirst)
    #expect(p.customAccountOrder.isEmpty)
    #expect(p.showSnapshotAge)
    #expect(p.notificationsEnabled)
    #expect(p.thresholds == [95, 80])
    #expect(p.notifyOnRecovery)
    #expect(p.notifyWindows == .both)
    #expect(p.quietHours == nil)
    #expect(p.foregroundInterval == 60)
    #expect(p.backgroundInterval == 300)
    #expect(p.refreshAfterWake)
    #expect(p.disabledProviders.isEmpty)
    #expect(p.hiddenAccounts.isEmpty)
}

@Test func anOlderSettingsFileGetsTheNewMenuBarDefault() throws {
    // Written by a build that had never heard of this setting. Every other
    // field has to survive, and the new one has to arrive at its default —
    // which is the new behaviour, so an upgrade brings it without being asked.
    let json = #"{"appearance":"dark","primaryWindow":"weekly"}"#
    let decoded = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
    #expect(decoded.menuBarAccount == .inUse)
    #expect(decoded.appearance == .dark)
    #expect(decoded.primaryWindow == .weekly)
}

@Test func theChoiceOfAccountSurvivesARoundTrip() throws {
    var p = Preferences.defaults
    p.menuBarAccount = .busiest
    let data = try JSONEncoder().encode(p)
    #expect(try JSONDecoder().decode(Preferences.self, from: data).menuBarAccount == .busiest)
}

@Test func thresholdsAreSortedDescendingAndDeduplicated() {
    var p = Preferences.defaults
    p.thresholds = [50, 95, 50, 80]
    #expect(p.normalized().thresholds == [95, 80, 50])
}

@Test func thresholdsOutsideRangeAreDropped() {
    var p = Preferences.defaults
    p.thresholds = [0, 50, 100, 140, -10]
    // zero and negatives are meaningless, above 100 is unreachable
    #expect(p.normalized().thresholds == [100, 50])
}

@Test func emptyThresholdListIsAllowed() {
    var p = Preferences.defaults
    p.thresholds = []
    #expect(p.normalized().thresholds.isEmpty)
}

@Test func intervalsAreClampedToAllowedRange() {
    var p = Preferences.defaults
    p.foregroundInterval = 5
    p.backgroundInterval = 7200
    let n = p.normalized()
    #expect(n.foregroundInterval == 30)
    #expect(n.backgroundInterval == 3600)
}

@Test func intervalsInsideRangeSurviveUntouched() {
    var p = Preferences.defaults
    p.foregroundInterval = 45
    p.backgroundInterval = 600
    let n = p.normalized()
    #expect(n.foregroundInterval == 45)
    #expect(n.backgroundInterval == 600)
}

@Test func survivesEncodingRoundTrip() throws {
    var p = Preferences.defaults
    p.appearance = .dark
    p.thresholds = [90]
    p.quietHours = QuietHours(startMinute: 23 * 60, endMinute: 9 * 60)
    p.disabledProviders = [.codex]
    p.hiddenAccounts = ["claude/u-1"]
    p.ordering = .custom
    p.customAccountOrder = ["codex/example", "claude/u-1"]

    let data = try JSONEncoder().encode(p)
    let back = try JSONDecoder().decode(Preferences.self, from: data)
    #expect(back == p)
}

@Suite struct SettingsForUpdating {

    /// A settings blob written before these two existed must not lose the other
    /// twenty on the way in. `Preferences` decodes field by field for exactly
    /// this, and every added setting is a fresh chance to forget it.
    @Test func settingsWrittenBeforeUpdatesExistedStillLoad() throws {
        let old = """
            {"appearance": "dark", "menuBarContent": "percent", "thresholds": [90],
             "backgroundInterval": 600}
            """
        let decoded = try JSONDecoder().decode(Preferences.self, from: Data(old.utf8))

        #expect(decoded.appearance == .dark)
        #expect(decoded.menuBarContent == .percent)
        #expect(decoded.backgroundInterval == 600)
        #expect(decoded.checksForUpdates,
                "a settings file from before the field existed lost its default")
        #expect(decoded.lastUpdateCheck == nil)
    }

    @Test func theAppLooksForUpdatesUnlessItIsToldNotTo() {
        #expect(Preferences.defaults.checksForUpdates)
        #expect(Preferences.defaults.lastUpdateCheck == nil)
    }

    /// Switched off, it stays off across a save and a read — the one thing a
    /// person who turned it off is relying on.
    @Test func refusingToCheckSurvivesAroundTrip() throws {
        var settings = Preferences.defaults
        settings.checksForUpdates = false
        settings.lastUpdateCheck = Date(timeIntervalSince1970: 1_800_000_000)

        let data = try JSONEncoder().encode(settings)
        let back = try JSONDecoder().decode(Preferences.self, from: data)

        #expect(!back.checksForUpdates)
        #expect(back.lastUpdateCheck == settings.lastUpdateCheck)
    }
}

@Test func theWindowIsFullUntilSomebodyAsksOtherwise() {
    #expect(Preferences.defaults.minimalWindow == false)
}

@Suite struct CustomAccountOrdering {
    @Test func olderSettingsKeepTheirOrderAndOtherChoices() throws {
        let old = Data(#"{"ordering":"byName","appearance":"dark","languageCode":"ru"}"#.utf8)
        let decoded = try JSONDecoder().decode(Preferences.self, from: old)
        #expect(decoded.ordering == .byName)
        #expect(decoded.customAccountOrder.isEmpty)
        #expect(decoded.appearance == .dark)
        #expect(decoded.languageCode == "ru")
    }

    @Test func malformedOrderDoesNotDiscardOtherSettings() throws {
        let data = Data(#"{"ordering":"custom","customAccountOrder":false,"appearance":"dark"}"#.utf8)
        let decoded = try JSONDecoder().decode(Preferences.self, from: data)
        #expect(decoded.ordering == .custom)
        #expect(decoded.customAccountOrder.isEmpty)
        #expect(decoded.appearance == .dark)
    }

    @Test func normalizationKeepsTheFirstPositionOfEachAccount() {
        var settings = Preferences.defaults
        settings.customAccountOrder = ["codex/example", "", "claude/example", "codex/example"]
        #expect(settings.normalized().customAccountOrder == ["codex/example", "claude/example"])
    }

    @Test func arrangingVisibleAccountsPreservesMissingAccountsSlots() {
        var settings = Preferences.defaults
        settings.customAccountOrder = ["first", "hidden", "second", "unavailable", "third"]
        settings.setCustomAccountOrder(["third", "first", "second", "new"])
        #expect(settings.customAccountOrder == ["third", "hidden", "first", "unavailable", "second", "new"])
    }

    @Test func anEmptyListDoesNotEraseSavedPositions() {
        var settings = Preferences.defaults
        settings.customAccountOrder = ["second", "first"]
        settings.setCustomAccountOrder([])
        #expect(settings.customAccountOrder == ["second", "first"])
    }
}

/// The field-by-field decoder, from the other direction: a settings file
/// written before this flag existed must keep every other answer in it.
@Test func settingsStoredBeforeTheFlagExistedSurviveTheUpgrade() throws {
    var stored = Preferences.defaults
    stored.languageCode = "ru"
    stored.thresholds = [90]
    stored.rowLayout = .rings

    let encoded = try JSONEncoder().encode(stored)
    var fields = try #require(
        try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    fields.removeValue(forKey: "minimalWindow")
    let older = try JSONSerialization.data(withJSONObject: fields)

    let read = try JSONDecoder().decode(Preferences.self, from: older)
    #expect(read.minimalWindow == false)
    #expect(read.languageCode == "ru")
    #expect(read.thresholds == [90])
    #expect(read.rowLayout == .rings)
}
