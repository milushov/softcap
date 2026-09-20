import Foundation

/// A published release, reduced to what offering one needs.
public struct Release: Sendable, Hashable, Identifiable {
    public var id: String { version.description }

    public let version: ReleaseVersion

    /// The release body, as the person who cut it wrote it. Markdown, and text
    /// that arrived over the network rather than a label written into a model —
    /// which is why it does not break the rule about strings in the core.
    public let notes: String

    /// Where to send somebody: the release page, or the App Store page.
    public let page: URL

    /// The files an update is installed from — the archive, its name in the
    /// checksum list, and the list. `nil` for a release the App Store publishes:
    /// the store installs those, and this app only says one exists. A release
    /// with nothing to download cannot be handed to `UpdateInstaller`, and it
    /// says so rather than downloading its own page.
    public let download: Download?

    public struct Download: Sendable, Hashable {
        public let archive: URL
        public let archiveName: String
        public let checksums: URL

        public init(archive: URL, archiveName: String, checksums: URL) {
            self.archive = archive
            self.archiveName = archiveName
            self.checksums = checksums
        }
    }

    public init(version: ReleaseVersion, notes: String, page: URL, download: Download?) {
        self.version = version
        self.notes = notes
        self.page = page
        self.download = download
    }

    /// A release with a build to install, the way GitHub publishes one.
    public init(
        version: ReleaseVersion, notes: String, archive: URL, archiveName: String,
        checksums: URL, page: URL
    ) {
        self.init(version: version, notes: notes, page: page,
                  download: Download(archive: archive, archiveName: archiveName, checksums: checksums))
    }
}
