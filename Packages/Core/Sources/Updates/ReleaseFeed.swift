import Foundation

/// The newest published release, read from GitHub.
public enum ReleaseFeed {

    public static func latestURL(owner: String, repository: String) -> URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest")!
    }

    /// Where a person is sent when the updater cannot finish by itself.
    public static func releasePage(owner: String, repository: String) -> URL {
        URL(string: "https://github.com/\(owner)/\(repository)/releases/latest")!
    }

    /// The newest release, or `nil` when it is not newer than what is running.
    ///
    /// A release older than the running app is not an update. A locally built
    /// app reports the marketing version alone and can be ahead of everything
    /// published; offering to move it backwards is not an offer worth making.
    public static func update(from data: Data, running: ReleaseVersion) throws -> Release? {
        // The version is read and compared before the release's files are
        // demanded. The workflow publishes the release and then uploads its
        // assets, so for that window `/releases/latest` answers with a release
        // that has no checksums beside it — and everyone, including everyone
        // already running the newest build, was told the newest release has no
        // build to download. Somebody with nothing to install should not be
        // shown a fault in something they do not need.
        let payload = try payload(from: data)
        let version = try version(of: payload)
        guard version > running else { return nil }
        return try release(from: payload, at: version)
    }

    /// The same, reading what the answer's status means first.
    ///
    /// A 404 is not a failure. It is what GitHub says when a repository has
    /// never published a release, which is the state this one was in the whole
    /// time the updater was being built — and the screen said "GitHub could not
    /// be reached. Check the connection and try again." over a connection that
    /// was working perfectly. Advice to go and fix the wrong thing is worse than
    /// no advice.
    ///
    /// Everything else that is not an answer is a failure, and the status goes
    /// into the log: a rate limit and an outage look identical on screen and are
    /// worth telling apart afterwards.
    public static func update(
        from data: Data, status: Int, running: ReleaseVersion
    ) throws -> Release? {
        switch status {
        case 200: try update(from: data, running: running)
        case 404: nil
        default:  throw UpdateFailure(kind: .network,
                                      diagnostic: "releases came back \(status)")
        }
    }

    public static func decode(_ data: Data) throws -> Release {
        let payload = try payload(from: data)
        return try release(from: payload, at: try version(of: payload))
    }

    // MARK: - three steps, so a caller can stop after the second

    private static func payload(from data: Data) throws -> Payload {
        do {
            return try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            // A rate-limited answer is HTML and an outage is a status page.
            // Neither is a release, and neither is worth a different sentence.
            throw UpdateFailure(kind: .malformedRelease,
                                diagnostic: "response did not decode: \(type(of: error))")
        }
    }

    private static func version(of payload: Payload) throws -> ReleaseVersion {
        guard !payload.draft, !payload.prerelease else {
            throw UpdateFailure(kind: .malformedRelease, diagnostic: "draft or prerelease")
        }
        guard let version = ReleaseVersion(payload.tagName) else {
            throw UpdateFailure(kind: .malformedRelease,
                                diagnostic: "tag is not a version: \(payload.tagName)")
        }
        return version
    }

    private static func release(
        from payload: Payload, at version: ReleaseVersion
    ) throws -> Release {
        // The zip, not the disk image: an image has to be mounted and the app
        // copied out of it, and the zip is published for exactly this.
        guard let archive = payload.assets.first(where: {
            $0.name.hasPrefix("Softcap-") && $0.name.hasSuffix(".zip")
        }) else {
            throw UpdateFailure(kind: .malformedRelease, diagnostic: "no zip asset")
        }

        // Without the sums there is nothing to check the download against, and
        // installing it unchecked is the wrong way to be forgiving.
        guard let sums = payload.assets.first(where: { $0.name == "SHA256SUMS.txt" }) else {
            throw UpdateFailure(kind: .malformedRelease, diagnostic: "no checksums asset")
        }

        return Release(
            version: version,
            notes: payload.body ?? "",
            archive: archive.browserDownloadURL,
            archiveName: archive.name,
            checksums: sums.browserDownloadURL,
            page: payload.htmlURL
        )
    }

    // MARK: -

    /// The fields this reads. Unknown keys are ignored, which is what a
    /// synthesised `Decodable` does and what keeps a new field on GitHub's side
    /// from becoming an app that can no longer find an update.
    private struct Payload: Decodable {
        let tagName: String
        let body: String?
        let draft: Bool
        let prerelease: Bool
        let htmlURL: URL
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body, draft, prerelease
            case htmlURL = "html_url"
            case assets
        }

        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }
    }
}
