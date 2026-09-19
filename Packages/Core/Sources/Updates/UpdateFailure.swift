import Foundation

/// What can go wrong on the way to a new version, as identifiers.
///
/// Shaped after `ProviderFailure` and for the same reason: the interface builds
/// the sentence, in the language the reader chose, and the diagnostic goes to
/// the log. A model that carried the sentence would have to be translated, and
/// `Packages/Core` holds no text meant to be read.
public struct UpdateFailure: Sendable, Hashable, Error {
    public enum Kind: Sendable, Hashable {
        /// GitHub could not be reached, or the download stopped.
        case network
        /// The newest release is missing the build it should carry.
        case malformedRelease
        /// What arrived is not what the release says it published.
        case checksumMismatch
        /// It arrived signed by somebody else.
        case signatureChanged
        /// The installed copy cannot be written where it sits.
        case notWritable
        /// The copy that is running is no longer at the path it was launched
        /// from — moved, renamed, or deleted while it ran. There is nothing to
        /// replace, and nowhere to put a replacement.
        case bundleGone
        /// The archive did not open, or held something other than the app.
        case unpackFailed
    }

    public let kind: Kind
    /// Detail for the log, not for a person: a status code, a file name, an
    /// exit status. Interface text is built from `kind`.
    public let diagnostic: String

    public init(kind: Kind, diagnostic: String = "") {
        self.kind = kind
        self.diagnostic = diagnostic
    }
}
