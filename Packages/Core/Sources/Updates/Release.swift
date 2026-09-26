import Foundation

/// A published release, reduced to what offering one needs.
public struct Release: Sendable, Hashable, Identifiable {
    public var id: String { version.description }

    public let version: ReleaseVersion

    /// The release body, as the person who cut it wrote it. Markdown, and text
    /// that arrived over the network rather than a label written into a model —
    /// which is why it does not break the rule about strings in the core.
    public let notes: String

    /// Where to send somebody when the install cannot finish by itself.
    public let page: URL

    /// The files an update is installed from — the archive, its name in the
    /// checksum list, and the list.
    ///
    /// It was optional for four days, so that the App Store lane could offer a
    /// release with nothing to download. That lane is gone — guideline
    /// 2.4.5(vii), `docs/DECISIONS.md` 2026-09-25 — and with it the only way to
    /// hold a release this app cannot install. `ReleaseFeed` already refuses a
    /// published release whose assets have not finished uploading, so the
    /// absence has one meaning again and the type says so.
    public let download: Download

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

    public init(version: ReleaseVersion, notes: String, page: URL, download: Download) {
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
