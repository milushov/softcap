import Testing
import Foundation
@testable import Updates

/// The App Store copy of the app learns about a newer version from the App
/// Store, not from GitHub: a release is on GitHub the minute the workflow ends
/// and on the store days later, when review ends, and a copy the store installs
/// must not offer a version the store does not have yet.
@Suite struct StoreListing_ReadsTheStoresOwnRecord {

    private func lookup(version: String, notes: String? = "• A thing.\n• Another.",
                        page: String = "https://apps.apple.com/us/app/softcap/id6811539739?mt=12&uo=4",
                        count: Int = 1) -> Data {
        let record: [String: Any] = [
            "bundleId": "app.softcap.Softcap", "kind": "mac-software", "trackId": 6811539739,
            "version": version, "trackViewUrl": page, "releaseNotes": notes as Any,
            "currentVersionReleaseDate": "2026-09-19T10:32:51Z",
        ]
        let payload: [String: Any] = ["resultCount": count, "results": count == 0 ? [] : [record]]
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    @Test func aNewerVersionOnTheStoreIsAnOffer() throws {
        let running = try #require(ReleaseVersion("0.1.25"))
        let found = try StoreListing.update(from: lookup(version: "0.1.31"), status: 200, running: running)
        let release = try #require(found)
        #expect(release.version.description == "0.1.31")
        #expect(release.page.host == "apps.apple.com")
        #expect(release.notes.hasPrefix("• A thing."))
        // The store installs its own releases; there is nothing here to download.
        #expect(release.download == nil)
    }

    @Test func theSameOrAnOlderVersionIsNotAnOffer() throws {
        let running = try #require(ReleaseVersion("0.1.31"))
        #expect(try StoreListing.update(from: lookup(version: "0.1.31"), status: 200, running: running) == nil)
        // A build ahead of the store — TestFlight, or a developer's own — is not
        // offered a move backwards.
        #expect(try StoreListing.update(from: lookup(version: "0.1.25"), status: 200, running: running) == nil)
    }

    /// The store answers `resultCount: 0` with a 200 when it has no record — an
    /// app not yet released, or a storefront it is not sold in. That is not an
    /// update and not an outage.
    @Test func noRecordIsNothingNewer() throws {
        let running = try #require(ReleaseVersion("0.1.25"))
        #expect(try StoreListing.update(from: lookup(version: "", count: 0), status: 200, running: running) == nil)
    }

    @Test func missingNotesAreAnEmptyString() throws {
        let running = try #require(ReleaseVersion("0.1.25"))
        let release = try #require(try StoreListing.update(
            from: lookup(version: "0.1.31", notes: nil), status: 200, running: running))
        #expect(release.notes.isEmpty)
    }

    @Test func anythingButAnAnswerIsANetworkFailure() throws {
        let running = try #require(ReleaseVersion("0.1.25"))
        #expect(throws: UpdateFailure.self) {
            try StoreListing.update(from: Data(), status: 503, running: running)
        }
        #expect(throws: UpdateFailure.self) {
            try StoreListing.update(from: Data("not json".utf8), status: 200, running: running)
        }
    }

    @Test func theLookupAsksByBundleIdentifier() {
        let url = StoreListing.lookupURL(bundleID: "app.softcap.Softcap")
        #expect(url.host == "itunes.apple.com")
        #expect(url.query?.contains("bundleId=app.softcap.Softcap") == true)
    }
}
