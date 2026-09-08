import Foundation
import CryptoKit

/// The `SHA256SUMS.txt` a release publishes, read by file name.
///
/// The release workflow writes it with `shasum -a 256 ./*.dmg ./*.zip`, so a
/// line is a digest, a run of spaces, and a path beginning `./`. The path is
/// reduced to its last component: the lookup is for a published asset, and the
/// prefix is an artefact of the directory the command ran in.
public struct Checksums: Sendable {
    private let byName: [String: String]

    public init(_ text: String) {
        var found: [String: String] = [:]
        let text = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        // Split on any newline and any whitespace, not on the two characters a
        // Mac happens to use. Swift counts "\r\n" as one Character, so
        // `split(separator: "\n")` does not match it at all and a file with
        // Windows endings arrives as a single line — which parses as nothing,
        // and every update is then refused as tampered with. Sums regenerated
        // off a Mac, or corrected in a browser, come back that way.
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2 else { continue }

            let digest = fields[0].lowercased()
            // A line that is not a checksum is skipped rather than stored.
            // Stored, it would be compared against and could never match, and a
            // mismatch is reported to the reader as a download that was
            // tampered with — an alarm raised by a blank line.
            guard digest.count == 64, digest.allSatisfy(\.isHexDigit) else { continue }

            // `shasum` writes an asterisk before a name it read as binary.
            var name = String(fields[1])
            if name.hasPrefix("*") { name.removeFirst() }
            found[(name as NSString).lastPathComponent] = digest
        }
        byName = found
    }

    public var count: Int { byName.count }

    public func digest(for fileName: String) -> String? { byName[fileName] }
}

extension Checksums {
    /// SHA-256 of a file, as lowercase hex — the spelling `shasum -a 256`
    /// writes, so the two can be compared as text.
    ///
    /// Read in chunks rather than into memory at once: a build is several
    /// megabytes today and there is no reason for it to be resident.
    public static func digest(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
