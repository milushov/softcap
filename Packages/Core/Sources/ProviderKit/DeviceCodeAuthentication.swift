import Foundation

/// A sign-in where the person carries a code to the service, rather than the
/// service carrying a reply back to us.
///
/// `BrowserAuthenticating` covers the other shape: open a browser, listen on a
/// loopback port, exchange the code that comes back. That needs the service to
/// accept a redirect to `localhost` and to exchange without a client secret,
/// and not every service does both. One that does neither offers this instead:
/// ask for a code, show it to the person, send them to a page to type it in,
/// and poll until they have.
///
/// The two protocols share no ancestor because they share no step. One binds a
/// socket and parses a request line; this one keeps a deadline and an interval
/// the server sets. A common base would exist only to have one.
public protocol DeviceCodeAuthenticating: Sendable {
    var provider: ProviderID { get }

    /// Asks for a code and the page to type it into.
    func requestCode() async throws -> DeviceCodeGrant

    /// One look at whether the person has finished.
    ///
    /// One step, not the whole loop: the caller owns the attempt — it is the
    /// one that can be cancelled, that holds the deadline, and that has a
    /// screen to put the code on. That is the same division
    /// `BrowserAuthenticating` has, where the provider says what to ask for and
    /// the app owns the browser.
    func poll(_ grant: DeviceCodeGrant) async throws -> DeviceCodePoll
}

/// What the service handed back when it was asked for a code.
public struct DeviceCodeGrant: Sendable, Hashable {
    /// The app's half, sent with every poll. Never shown to anybody.
    public let deviceCode: String
    /// The person's half, short enough to read off a screen and type.
    public let userCode: String
    /// Where they type it.
    public let verificationURL: URL
    /// The least time the service will tolerate between polls. Polling faster
    /// earns a `slowDown`, which is the service asking once politely.
    public let interval: TimeInterval
    /// When the code stops working. After this there is nothing to wait for.
    public let expiresAt: Date

    public init(
        deviceCode: String, userCode: String, verificationURL: URL,
        interval: TimeInterval, expiresAt: Date
    ) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURL = verificationURL
        self.interval = interval
        self.expiresAt = expiresAt
    }
}

public enum DeviceCodePoll: Sendable {
    /// Nobody has typed it yet. Wait the interval and ask again.
    case pending
    /// Asked too often. The new interval replaces the granted one for the rest
    /// of the attempt — the service raises it rather than restating it, and an
    /// attempt that kept using the original would go on being told off.
    case slowDown(TimeInterval)
    /// Done. The account and its tokens.
    case granted(AuthenticatedAccount)
}

/// The two ways an attempt ends without an account, and they read differently
/// to the person waiting: one of them they did themselves.
public struct DeviceCodeRejected: Error, Sendable, Hashable {
    public enum Reason: Sendable, Hashable {
        /// They pressed the button that says no.
        case denied
        /// The code went stale before they got to it.
        case expired
    }

    public let reason: Reason

    public init(reason: Reason) { self.reason = reason }
}
