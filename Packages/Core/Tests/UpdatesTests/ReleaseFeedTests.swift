import Testing
import Foundation
@testable import Updates

@Suite struct DecodingTheReleaseFeed {

    /// Trimmed from a real response: the fields this reads, and two it ignores,
    /// so a decoder written to refuse unknown keys would be caught here.
    private func payload(
        tag: String = "v0.1.47",
        draft: Bool = false,
        prerelease: Bool = false,
        assets: String = """
            {"name": "Softcap-0.1.47.dmg", "browser_download_url": "https://github.com/milushov/softcap/releases/download/v0.1.47/Softcap-0.1.47.dmg", "size": 4100000},
            {"name": "Softcap-0.1.47.zip", "browser_download_url": "https://github.com/milushov/softcap/releases/download/v0.1.47/Softcap-0.1.47.zip", "size": 3900000},
            {"name": "SHA256SUMS.txt", "browser_download_url": "https://github.com/milushov/softcap/releases/download/v0.1.47/SHA256SUMS.txt", "size": 300}
            """
    ) -> Data {
        Data("""
            {
              "id": 12345,
              "tag_name": "\(tag)",
              "name": "0.1.47",
              "draft": \(draft),
              "prerelease": \(prerelease),
              "html_url": "https://github.com/milushov/softcap/releases/tag/\(tag)",
              "body": "Built from `abc1234`.\\n\\n- something changed",
              "assets": [\(assets)]
            }
            """.utf8)
    }

    @Test func areleaseCarriesItsVersionNotesAndArchive() throws {
        let release = try ReleaseFeed.decode(payload())
        #expect(release.version == ReleaseVersion("0.1.47"))
        #expect(release.download.archiveName == "Softcap-0.1.47.zip")
        #expect(release.notes.contains("something changed"))
        #expect(release.download.checksums.lastPathComponent == "SHA256SUMS.txt")
    }

    /// The zip, not the disk image. An image has to be mounted and the app
    /// copied out of it; the zip is what `ditto` opens in one step, and it is
    /// published for exactly this.
    @Test func theArchiveIsTheZipAndNotTheImage() throws {
        #expect(try ReleaseFeed.decode(payload()).download.archive.pathExtension == "zip")
    }

    @Test func areleaseWithNoBuildIsMalformed() {
        let assets = """
            {"name": "SHA256SUMS.txt", "browser_download_url": "https://github.com/milushov/softcap/releases/download/v1/SHA256SUMS.txt", "size": 30}
            """
        let error = #expect(throws: UpdateFailure.self) {
            try ReleaseFeed.decode(payload(assets: assets))
        }
        #expect(error?.kind == .malformedRelease)
    }

    /// The sums are how the download is checked. A release without them is not
    /// one this app can install, and installing it unchecked is the wrong way
    /// to be forgiving.
    @Test func areleaseWithNoChecksumsIsMalformed() {
        let assets = """
            {"name": "Softcap-0.1.47.zip", "browser_download_url": "https://github.com/milushov/softcap/releases/download/v1/Softcap-0.1.47.zip", "size": 39}
            """
        let error = #expect(throws: UpdateFailure.self) {
            try ReleaseFeed.decode(payload(assets: assets))
        }
        #expect(error?.kind == .malformedRelease)
    }

    @Test func atagThatIsNotAversionIsMalformed() {
        let error = #expect(throws: UpdateFailure.self) {
            try ReleaseFeed.decode(payload(tag: "nightly"))
        }
        #expect(error?.kind == .malformedRelease)
    }

    /// `/releases/latest` excludes both already. Refusing them here as well
    /// keeps the rule in the code rather than only in the shape of a URL, where
    /// the next person to reach for `/releases` would not find it.
    @Test func adraftIsNotArelease() {
        #expect(throws: UpdateFailure.self) { try ReleaseFeed.decode(payload(draft: true)) }
    }

    @Test func aprereleaseIsNotArelease() {
        #expect(throws: UpdateFailure.self) { try ReleaseFeed.decode(payload(prerelease: true)) }
    }

    /// A rate-limited answer is HTML and an outage is a status page. Neither is
    /// a release, and neither should arrive as a crash.
    @Test func somethingThatIsNotJsonIsMalformed() {
        let error = #expect(throws: UpdateFailure.self) {
            try ReleaseFeed.decode(Data("<html>rate limited</html>".utf8))
        }
        #expect(error?.kind == .malformedRelease)
    }

    // MARK: - what counts as an update

    @Test func anewerReleaseIsAnUpdate() throws {
        let running = try #require(ReleaseVersion("0.1.42"))
        #expect(try ReleaseFeed.update(from: payload(), running: running) != nil)
    }

    @Test func thesameVersionIsNotAnUpdate() throws {
        let running = try #require(ReleaseVersion("0.1.47"))
        #expect(try ReleaseFeed.update(from: payload(), running: running) == nil)
    }

    /// A locally built app can be ahead of the newest release. Offering to move
    /// it backwards is not an update.
    @Test func anolderReleaseIsNotAnUpdate() throws {
        let running = try #require(ReleaseVersion("0.2.0"))
        #expect(try ReleaseFeed.update(from: payload(), running: running) == nil)
    }

    // MARK: - what the answer's status means

    /// A repository that has never published a release answers 404, and that is
    /// not a failure — it is the state this one was in while the updater was
    /// being built. Reported as one it read "GitHub could not be reached. Check
    /// the connection and try again.", which sends somebody to fix a connection
    /// that is working perfectly.
    @Test func arepositoryWithNoReleasesIsNotAfailure() throws {
        let running = try #require(ReleaseVersion("0.1"))
        #expect(try ReleaseFeed.update(from: Data(), status: 404, running: running) == nil)
    }

    @Test func anAnswerIsReadOnlyWhenItIsOne() throws {
        let running = try #require(ReleaseVersion("0.1.42"))
        #expect(try ReleaseFeed.update(from: payload(), status: 200, running: running) != nil)
    }

    /// Anything else is a failure, and says which one in the log: a rate limit
    /// and an outage are both worth telling apart afterwards.
    @Test func anythingElseIsAfailureThatNamesItsStatus() throws {
        let running = try #require(ReleaseVersion("0.1"))
        for status in [403, 429, 500, 503] {
            let error = #expect(throws: UpdateFailure.self) {
                try ReleaseFeed.update(from: Data(), status: status, running: running)
            }
            #expect(error?.kind == .network)
            #expect(error?.diagnostic.contains("\(status)") == true,
                    "the log does not say which status came back")
        }
    }

    @Test func theFeedUrlNamesTheRepository() {
        #expect(ReleaseFeed.latestURL(owner: "milushov", repository: "softcap").absoluteString
                == "https://api.github.com/repos/milushov/softcap/releases/latest")
    }
}

/// The order the release is taken apart in.
///
/// The workflow publishes the release and then uploads its files, so for that
/// window `/releases/latest` answers with a release that has no checksums beside
/// it. Everyone was told "The newest release has no build to download." —
/// including everyone already running the newest build, who had nothing to
/// download in the first place.
@Suite struct AreleaseIsComparedBeforeItIsTakenApart {

    private func halfPublished(tag: String) -> Data {
        Data("""
            {
              "tag_name": "\(tag)",
              "draft": false,
              "prerelease": false,
              "html_url": "https://github.com/milushov/softcap/releases/tag/\(tag)",
              "body": "",
              "assets": []
            }
            """.utf8)
    }

    @Test func areleaseYouAreAlreadyOnIsNotAfault() throws {
        let running = try #require(ReleaseVersion("0.1.47"))
        #expect(try ReleaseFeed.update(from: halfPublished(tag: "v0.1.47"), running: running) == nil)
    }

    @Test func anolderHalfPublishedReleaseIsNotAfaultEither() throws {
        let running = try #require(ReleaseVersion("0.2.0"))
        #expect(try ReleaseFeed.update(from: halfPublished(tag: "v0.1.47"), running: running) == nil)
    }

    /// The other half: a release that really is newer and really has nothing to
    /// install still says so, or the reorder would have hidden a genuine fault.
    @Test func anewerReleaseWithNothingInItStillReports() throws {
        let running = try #require(ReleaseVersion("0.1.42"))
        let error = #expect(throws: UpdateFailure.self) {
            try ReleaseFeed.update(from: halfPublished(tag: "v0.1.47"), running: running)
        }
        #expect(error?.kind == .malformedRelease)
    }
}
