import Testing
import Foundation
import ProviderKit
import Preferences
@testable import StatusUI

@Suite struct SharedSnapshotExchange {

    private static func makeSnapshot(accounts: Int) -> SharedSnapshot {
        let now = Date(timeIntervalSince1970: 1_800_000)
        return SharedSnapshot(
            accounts: (0..<accounts).map { index in
                AccountSnapshot(
                    id: "claude/u-\(index)", provider: .claude,
                    displayName: "user\(index)@example.com", planLabel: "Max 20x",
                    windows: [
                        LimitWindow(id: "session", percent: Double(index) * 10,
                                    resetsAt: now.addingTimeInterval(3600)),
                        LimitWindow(id: "weekly", percent: Double(index) * 5, resetsAt: nil),
                    ],
                    freshness: .live(now), failure: nil
                )
            },
            capturedAt: now, rowLayout: .rings, showSnapshotAge: false, languageCode: "ar"
        )
    }

    private static func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot-\(UUID().uuidString).json")
    }

    @Test func survivesTheRoundTrip() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let original = Self.makeSnapshot(accounts: 3)
        SharedStore.write(original, to: url)

        let restored = try #require(SharedStore.read(from: url))
        #expect(restored == original)
    }

    /// Everything the widget draws must survive the crossing, including the
    /// language and the layout — the widget has no other source for them.
    @Test func carriesSettingsTheWidgetNeeds() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        SharedStore.write(Self.makeSnapshot(accounts: 1), to: url)
        let restored = try #require(SharedStore.read(from: url))

        #expect(restored.languageCode == "ar")
        #expect(restored.rowLayout == .rings)
        #expect(restored.showSnapshotAge == false)
    }

    @Test func failureStateCrossesIntact() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let snapshot = SharedSnapshot(
            accounts: [AccountSnapshot(
                id: "codex/x", provider: .codex, displayName: "T", planLabel: "Plus",
                windows: [], freshness: .snapshot(Date(timeIntervalSince1970: 1)),
                failure: ProviderFailure(kind: .noData, diagnostic: "no codex session files")
            )],
            capturedAt: Date(timeIntervalSince1970: 2),
            rowLayout: .twoWindows, showSnapshotAge: true, languageCode: nil
        )
        SharedStore.write(snapshot, to: url)

        let restored = try #require(SharedStore.read(from: url))
        #expect(restored.accounts.first?.failure?.kind == .noData)
        #expect(restored.accounts.first?.freshness.isStale == true)
    }

    @Test func missingFileReadsAsNothing() {
        // The widget runs before the app has ever polled — that is normal.
        #expect(SharedStore.read(from: Self.temporaryURL()) == nil)
    }

    @Test func corruptFileReadsAsNothingRatherThanCrashing() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try Data("half a fi".utf8).write(to: url)
        #expect(SharedStore.read(from: url) == nil)
    }

    @Test func rewritingReplacesRatherThanAppends() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        SharedStore.write(Self.makeSnapshot(accounts: 5), to: url)
        SharedStore.write(Self.makeSnapshot(accounts: 1), to: url)

        let restored = try #require(SharedStore.read(from: url))
        #expect(restored.accounts.count == 1)
    }
}

/// A snapshot written by an older build must still decode.
///
/// `pollingEvery` was added so the widget could tell a recent reading from an
/// overdue one. A widget that fails to read the file falls back to "No accounts
/// found" — which is a lie about the accounts, told because of a field.
@Suite struct AnOlderSnapshotStillDecodes {

    /// Exactly the shape the app wrote before `pollingEvery` existed.
    private static let beforeThePollingField = """
    {
      "accounts": [],
      "capturedAt": 776000000,
      "rowLayout": "twoWindows",
      "showSnapshotAge": true
    }
    """

    @Test func theFieldIsOptionalNotRequired() throws {
        let data = Data(Self.beforeThePollingField.utf8)
        let decoded = try JSONDecoder().decode(SharedSnapshot.self, from: data)
        #expect(decoded.pollingEvery == nil)
        #expect(decoded.rowLayout == .twoWindows)
        #expect(decoded.showSnapshotAge)
    }

    @Test func aNewOneCarriesIt() throws {
        let snapshot = SharedSnapshot(
            accounts: [], capturedAt: Date(timeIntervalSince1970: 776_000_000),
            rowLayout: .compact, showSnapshotAge: false,
            languageCode: "ru", pollingEvery: 1800
        )
        let round = try JSONDecoder().decode(
            SharedSnapshot.self, from: JSONEncoder().encode(snapshot)
        )
        #expect(round.pollingEvery == 1800)
        #expect(round == snapshot)
    }
}

/// A snapshot a later build wrote, or an older one, still reads.
///
/// A widget that cannot decode the file shows "No accounts found" — which reads
/// as an app nobody has set up, not as a file it could not parse. So a field it
/// does not recognise, or one it expected and did not find, must cost that field
/// and nothing else.
@Suite struct ASnapshotFromAnotherBuild {

    private static func encoded(_ dict: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: dict)
    }

    @Test func aMissingFieldCostsOnlyItself() throws {
        let full = SharedSnapshot(
            accounts: [], capturedAt: Date(timeIntervalSince1970: 700_000_000),
            rowLayout: .rings, showSnapshotAge: false,
            languageCode: "ru", pollingEvery: 900
        )
        var dict = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(full)
        ) as! [String: Any]
        dict.removeValue(forKey: "rowLayout")

        let back = try JSONDecoder().decode(SharedSnapshot.self, from: Self.encoded(dict))
        #expect(back.languageCode == "ru", "the whole snapshot was lost with one field")
        #expect(back.pollingEvery == 900)
        #expect(back.rowLayout == Preferences.defaults.rowLayout)
    }

    @Test func anUnknownFieldIsIgnored() throws {
        var dict = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(
                SharedSnapshot(accounts: [], capturedAt: Date(timeIntervalSince1970: 1),
                               rowLayout: .compact, showSnapshotAge: true,
                               languageCode: nil, pollingEvery: nil)
            )
        ) as! [String: Any]
        dict["somethingTheNextBuildAdded"] = 42

        let back = try JSONDecoder().decode(SharedSnapshot.self, from: Self.encoded(dict))
        #expect(back.rowLayout == .compact)
    }
}

/// The rows inside the snapshot, which is what the widget draws.
@Suite struct TheAccountsInsideASnapshot {

    @Test func oneUnreadableRowCostsThatRow() throws {
        let json = """
        {"capturedAt":700000000,"rowLayout":"twoWindows","showSnapshotAge":true,
         "accounts":[
           {"id":"claude/a","provider":"claude","displayName":"A","planLabel":"Max 20x",
            "windows":[],"freshness":{"live":{"_0":700000000}}},
           {"provider":"claude","displayName":"no id here"},
           {"id":"codex/c","provider":"codex","displayName":"C","planLabel":"Plus",
            "windows":[],"freshness":{"live":{"_0":700000000}}}
         ]}
        """
        let back = try JSONDecoder().decode(SharedSnapshot.self, from: Data(json.utf8))
        #expect(back.accounts.count == 2, "one bad row took the others with it")
        #expect(back.accounts.map(\.id) == ["claude/a", "codex/c"])
    }

    /// A row from a build that knew one field fewer still draws.
    @Test func aRowMissingAFieldKeepsWhatItHas() throws {
        let json = """
        {"capturedAt":700000000,"rowLayout":"twoWindows","showSnapshotAge":true,
         "accounts":[{"id":"claude/a","provider":"claude","windows":[],
                      "freshness":{"live":{"_0":700000000}}}]}
        """
        let back = try JSONDecoder().decode(SharedSnapshot.self, from: Data(json.utf8))
        #expect(back.accounts.count == 1)
        #expect(back.accounts.first?.displayName == "claude/a",
                "a row with no name should fall back to its identifier")
        #expect(back.accounts.first?.planLabel == "—")
    }

    /// A row with no identifier is not a row.
    @Test func aRowWithoutAnIdentifierIsRefused() throws {
        let json = """
        {"capturedAt":700000000,"rowLayout":"twoWindows","showSnapshotAge":true,
         "accounts":[{"provider":"claude","displayName":"nameless"}]}
        """
        let back = try JSONDecoder().decode(SharedSnapshot.self, from: Data(json.utf8))
        #expect(back.accounts.isEmpty)
    }
}
