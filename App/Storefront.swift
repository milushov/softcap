import Foundation
import Updates

/// Where the App Store copy of this app comes from, named once.
///
/// The counterpart of `Repository`, for the other lane: the copy the store
/// installs learns about a newer version from the store's own record and sends
/// a person to the store's own page. The numeric identifier is the one the
/// landing page's button carries.
enum Storefront {
    static let id = "6811539739"
    static let bundleID = "app.softcap.Softcap"

    /// The page, as a link a browser can show.
    static let page = URL(string: "https://apps.apple.com/app/id\(id)")!

    /// The same page opened in the App Store app itself, which is where the
    /// Update button is — a browser would only bounce there after a moment
    /// showing the web page.
    static let inStore = URL(string: "macappstore://apps.apple.com/app/id\(id)")!

    static let lookup = StoreListing.lookupURL(bundleID: bundleID)
}
