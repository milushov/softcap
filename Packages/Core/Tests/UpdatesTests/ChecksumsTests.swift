import Testing
import Foundation
@testable import Updates

@Suite struct ReadingTheChecksums {

    /// Exactly what `shasum -a 256 ./*.dmg ./*.zip` writes, which is what the
    /// release workflow runs.
    private let published = """
        3b1f8c2d4e5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c  ./Softcap-0.1.47.dmg
        9f8e7d6c5b4a39281706f5e4d3c2b1a09f8e7d6c5b4a39281706f5e4d3c2b1a0  ./Softcap.dmg
        1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef  ./Softcap-0.1.47.zip
        """

    @Test func afileIsFoundByItsNameWithoutThePath() {
        let sums = Checksums(published)
        #expect(sums.digest(for: "Softcap-0.1.47.zip")
                == "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
    }

    @Test func everyPublishedFileIsThere() {
        #expect(Checksums(published).count == 3)
    }

    @Test func afileNotPublishedHasNoDigest() {
        #expect(Checksums(published).digest(for: "Softcap-0.1.48.zip") == nil)
    }

    /// `shasum` marks a binary read with an asterisk on some systems, and the
    /// name must survive it.
    @Test func theBinaryMarkerIsNotPartOfTheName() {
        let sums = Checksums(
            "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef *Softcap-0.1.47.zip")
        #expect(sums.digest(for: "Softcap-0.1.47.zip") != nil)
    }

    @Test func digestsComeBackInOneCase() {
        let sums = Checksums(
            "ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890  ./x.zip")
        #expect(sums.digest(for: "x.zip")
                == "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890")
    }

    /// A line that is not a digest and a name is skipped rather than stored: a
    /// blank line, a heading somebody added, a truncated file. Stored, it would
    /// be compared against and never match, and a mismatch is reported to the
    /// reader as a download that was tampered with.
    @Test func whatIsNotAchecksumLineIsSkipped() {
        let sums = Checksums("""

            # SHA256
            not-a-digest  ./Softcap-0.1.47.zip
            1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef  ./real.zip
            deadbeef  ./tooshort.zip
            """)
        #expect(sums.count == 1)
        #expect(sums.digest(for: "real.zip") != nil)
    }

    @Test func anEmptyFileHoldsNothing() {
        #expect(Checksums("").count == 0)
    }

    /// The digest is compared against a line `shasum` wrote, so it has to be
    /// spelled the way `shasum` spells one: lowercase hex, no separators.
    /// Checked against the published answer for the empty input rather than
    /// against another call to the same code.
    @Test func adigestIsSpelledTheWayShasumSpellsOne() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("softcap-digest-\(UUID().uuidString)")
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(try Checksums.digest(ofFileAt: file)
                == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    /// Read in chunks, so a file larger than one chunk is where an off-by-one
    /// in the loop would show.
    @Test func afileLargerThanOneChunkHashesWhole() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("softcap-digest-\(UUID().uuidString)")
        try Data(repeating: 0, count: (1 << 20) + 7).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let mine = try Checksums.digest(ofFileAt: file)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        process.arguments = ["-a", "256", file.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()

        #expect(output.hasPrefix(mine), "shasum wrote \(output.prefix(64)), we wrote \(mine)")
    }
}

/// Line endings and separators this file can arrive with.
///
/// The parser split on the literal "\n" and on the literal " ". Swift counts
/// "\r\n" as one Character, so that split does not match it: a file with
/// Windows endings came back as one line, parsed as nothing, and every update
/// was then refused with "What arrived is not what the release published" —
/// the accusation the parser's own comment says it exists to prevent.
@Suite struct ChecksumsArriveInMoreThanOneShape {

    private let digest = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"

    @Test func windowsEndingsAreStillLines() {
        let sums = Checksums("\(digest)  ./a.zip\r\n\(digest)  ./b.zip\r\n")
        #expect(sums.count == 2)
        #expect(sums.digest(for: "a.zip") == digest)
    }

    @Test func aloneCarriageReturnIsStillAline() {
        #expect(Checksums("\(digest)  ./a.zip\r\(digest)  ./b.zip").count == 2)
    }

    @Test func abyteOrderMarkDoesNotEatTheFirstLine() {
        #expect(Checksums("\u{FEFF}\(digest)  ./a.zip").digest(for: "a.zip") == digest)
    }

    @Test func atabSeparatesAsWellAsAspace() {
        #expect(Checksums("\(digest)\t./a.zip").digest(for: "a.zip") == digest)
    }
}
