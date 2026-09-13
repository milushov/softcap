import Foundation
import Updates

/// Where this app comes from, named once.
///
/// Two screens need it and they must not disagree: Updates reads the release
/// feed, Contribute sends a person to the source. The same pair of words written
/// out twice is the shape of a link that goes on pointing at the old place after
/// a move — the release workflow had exactly that bug about the version number.
enum Repository {
    static let owner = "milushov"
    static let name = "softcap"

    /// What a person is shown rather than a URL to read aloud.
    static var label: String { "github.com/\(owner)/\(name)" }

    static var page: URL { URL(string: "https://github.com/\(owner)/\(name)")! }
    static var issues: URL { page.appendingPathComponent("issues") }
    static var releases: URL { ReleaseFeed.releasePage(owner: owner, repository: name) }
}
