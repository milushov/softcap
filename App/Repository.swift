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
    static let label = "github.com/\(owner)/\(name)"

    // `let`, not a computed `var`: a view's body is read on every redraw, and
    // these would have re-interpolated the text and re-parsed — and force
    // unwrapped — the URL each time it was.
    static let page = URL(string: "https://github.com/\(owner)/\(name)")!
    static let issues = page.appendingPathComponent("issues")
    /// `blob/main`, so the file is shown rather than downloaded.
    static let licence = page.appendingPathComponent("blob/main/LICENSE")
    static let releases = ReleaseFeed.releasePage(owner: owner, repository: name)
}
