import Foundation

/// A published release, reduced to what installing one needs.
public struct Release: Sendable, Hashable, Identifiable {
    public var id: String { version.description }

    public let version: ReleaseVersion

    /// The release body, as the person who cut it wrote it. Markdown, and text
    /// that arrived over the network rather than a label written into a model —
    /// which is why it does not break the rule about strings in the core.
    public let notes: String

    public let archive: URL
    public let archiveName: String
    public let checksums: URL

    /// Where to send somebody when the updater cannot finish.
    public let page: URL

    public init(
        version: ReleaseVersion, notes: String, archive: URL, archiveName: String,
        checksums: URL, page: URL
    ) {
        self.version = version
        self.notes = notes
        self.archive = archive
        self.archiveName = archiveName
        self.checksums = checksums
        self.page = page
    }
}
