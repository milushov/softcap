import Foundation

/// The newest version the App Store is selling, read from the store's own
/// lookup record.
///
/// The copy of this app that comes from the App Store is installed and updated
/// by the store, and it cannot learn about a newer version from GitHub: a
/// release is on GitHub the minute the workflow ends and on the store days
/// later, when review ends, and for those days the store copy would be offering
/// a version its owner could not have. So it asks the store. The lookup is the
/// public record behind every App Store page — no key, no account, one request
/// — and the honest limit of it is that it runs a few hours behind the
/// storefront, which for "is there a newer one" is close enough.
///
/// What comes back has no files in it. The store installs its own releases,
/// and it will not do so while the app is running — it asks the person to quit
/// first — which is exactly why this app has to say that a newer version
/// exists: a menu bar app that is never quit is never updated by the store on
/// its own.
public enum StoreListing {

    public static func lookupURL(bundleID: String) -> URL {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [URLQueryItem(name: "bundleId", value: bundleID)]
        return components.url!
    }

    /// The store's release, or `nil` when it is not newer than what is running.
    ///
    /// A build ahead of the store — TestFlight, or a developer's own — is not
    /// offered a move backwards, for the reason `ReleaseFeed` gives.
    public static func update(from data: Data, status: Int, running: ReleaseVersion) throws -> Release? {
        guard status == 200 else {
            throw UpdateFailure(kind: .network, diagnostic: "lookup came back \(status)")
        }
        let answer: Answer
        do {
            answer = try JSONDecoder().decode(Answer.self, from: data)
        } catch {
            throw UpdateFailure(kind: .network, diagnostic: "lookup was not the record expected")
        }
        // No record is an answer, not a fault: an app not yet on sale, or a
        // storefront it is not sold in, and in neither case is there an update.
        guard let record = answer.results.first else { return nil }
        guard let version = ReleaseVersion(record.version) else {
            throw UpdateFailure(kind: .network,
                                diagnostic: "lookup version unreadable: \(record.version)")
        }
        guard version > running else { return nil }
        return Release(version: version, notes: record.releaseNotes ?? "",
                       page: record.trackViewUrl, download: nil)
    }

    /// The fields this reads. Unknown keys are ignored, which is what a
    /// record with fifty of them needs.
    private struct Answer: Decodable {
        let results: [Record]
    }

    private struct Record: Decodable {
        let version: String
        let trackViewUrl: URL
        let releaseNotes: String?
    }
}
