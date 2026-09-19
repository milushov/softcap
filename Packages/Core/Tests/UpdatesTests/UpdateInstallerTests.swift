import Testing
import Foundation
import ProviderKit
@testable import Updates

@Suite struct InstallingAnUpdate {

    // MARK: - the world the installer is given

    /// Hands back a file already on disk, so the whole install runs without a
    /// network and without a server.
    private struct FileOnDisk: FileDownloader {
        let file: URL
        var remember: Handed?

        func download(
            _ url: URL, progress: @escaping @Sendable (Double) -> Void
        ) async throws -> URL {
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("softcap-test-\(UUID().uuidString)")
            try FileManager.default.copyItem(at: file, to: copy)
            remember?.record(copy)
            progress(1)
            return copy
        }
    }

    /// Answers every GET with one body: the only GET the installer makes is for
    /// the checksums.
    private struct OneAnswer: HTTPClient {
        let body: String
        func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
            (Data(body.utf8), 200)
        }
        func post(
            _ url: URL, headers: [String: String], body: Data
        ) async throws -> (Data, Int) {
            (Data(), 405)
        }
    }

    // MARK: - building a bundle and zipping it, as the release does

    private func makeBundle(
        in directory: URL, version: String, identifier: String = "app.softcap.Softcap",
        signed: Bool = false
    ) throws -> URL {
        let app = directory.appendingPathComponent("Softcap.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(
            at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
            <key>CFBundleIdentifier</key><string>\(identifier)</string>
            <key>CFBundleShortVersionString</key><string>\(version)</string>
            <key>CFBundleExecutable</key><string>Softcap</string>
            </dict></plist>
            """
        try plist.write(
            to: contents.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        // A real Mach-O rather than a script: codesign seals an executable, and
        // the point of signing these is to be able to break the seal.
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: "/bin/echo"),
            to: contents.appendingPathComponent("MacOS/Softcap"))

        if signed { try adHocSign(app) }
        return app
    }

    /// Ad-hoc, which needs no certificate and is what a release without one
    /// carries. It identifies nobody and still seals the bundle.
    private func adHocSign(_ app: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--sign", "-", app.path]
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "the fixture bundle would not sign")
    }

    private func zip(_ app: URL, to archive: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", app.path, archive.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "the fixture archive was not built")
    }

    private func scratch() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("softcap-install-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func subdirectory(_ name: String, of parent: URL) throws -> URL {
        let directory = parent.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func release(
        version: String, archiveName: String = "Softcap-0.1.47.zip"
    ) throws -> Release {
        let base = "https://github.com/milushov/softcap/releases/download/v\(version)"
        return Release(
            version: try #require(ReleaseVersion(version)),
            notes: "",
            archive: URL(string: "\(base)/\(archiveName)")!,
            archiveName: archiveName,
            checksums: URL(string: "\(base)/SHA256SUMS.txt")!,
            page: URL(string: "https://github.com/milushov/softcap/releases/latest")!
        )
    }

    private func versionOfApp(at bundle: URL) throws -> String {
        let plist = try String(
            contentsOf: bundle.appendingPathComponent("Contents/Info.plist"), encoding: .utf8)
        return plist
    }

    // MARK: - the guard this suite exists for

    /// Nothing is installed that did not match what the release published.
    ///
    /// This is the whole security of the thing. The download is not quarantined
    /// — `URLSession` does not mark a file the way a browser does — so nothing
    /// downstream will ask a second time.
    @Test func adownloadThatDoesNotMatchIsNotInstalled() async throws {
        let scratch = try scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let source = try makeBundle(in: try subdirectory("staging", of: scratch), version: "0.1.47")
        let archive = scratch.appendingPathComponent("Softcap-0.1.47.zip")
        try zip(source, to: archive)

        let installed = try makeBundle(
            in: try subdirectory("Applications", of: scratch), version: "0.1.42")
        let before = try versionOfApp(at: installed)

        let wrong = String(repeating: "a", count: 64)
        let installer = UpdateInstaller(
            downloader: FileOnDisk(file: archive),
            http: OneAnswer(body: "\(wrong)  ./Softcap-0.1.47.zip")
        )

        let error = await #expect(throws: UpdateFailure.self) {
            try await installer.install(
                try release(version: "0.1.47"), replacing: installed) { _ in }
        }
        #expect(error?.kind == .checksumMismatch)
        #expect(try versionOfApp(at: installed) == before,
                "the installed app was touched by a download that did not match")
    }

    /// A checksum file with no line for this archive is the same refusal: there
    /// is nothing to compare against, and installing unchecked is not the
    /// forgiving thing to do.
    @Test func achecksumFileThatDoesNotMentionTheArchiveIsArefusal() async throws {
        let scratch = try scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let source = try makeBundle(in: try subdirectory("staging", of: scratch), version: "0.1.47")
        let archive = scratch.appendingPathComponent("Softcap-0.1.47.zip")
        try zip(source, to: archive)
        let installed = try makeBundle(
            in: try subdirectory("Applications", of: scratch), version: "0.1.42")

        let installer = UpdateInstaller(
            downloader: FileOnDisk(file: archive),
            http: OneAnswer(body: "\(String(repeating: "b", count: 64))  ./something-else.zip")
        )

        let error = await #expect(throws: UpdateFailure.self) {
            try await installer.install(
                try release(version: "0.1.47"), replacing: installed) { _ in }
        }
        #expect(error?.kind == .checksumMismatch)
    }

    // MARK: - the happy path

    @Test func amatchingDownloadReplacesTheApp() async throws {
        let scratch = try scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let source = try makeBundle(in: try subdirectory("staging", of: scratch), version: "0.1.47")
        let archive = scratch.appendingPathComponent("Softcap-0.1.47.zip")
        try zip(source, to: archive)
        let installed = try makeBundle(
            in: try subdirectory("Applications", of: scratch), version: "0.1.42")

        let installer = UpdateInstaller(
            downloader: FileOnDisk(file: archive),
            http: OneAnswer(body: "\(try Checksums.digest(ofFileAt: archive))  ./Softcap-0.1.47.zip")
        )

        let phases = Phases()
        try await installer.install(
            try release(version: "0.1.47"), replacing: installed
        ) { phases.record($0) }

        #expect(try versionOfApp(at: installed).contains("0.1.47"),
                "the app in place is still the old one")
        #expect(phases.named == ["downloading", "verifying", "installing"])
    }

    /// A zip that opens into something other than the app is not installed,
    /// however well its checksum matches — a matching checksum only says the
    /// bytes are the ones published, not that they are the right ones.
    @Test func anarchiveHoldingSomethingElseIsRefused() async throws {
        let scratch = try scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let stranger = try makeBundle(
            in: try subdirectory("staging", of: scratch),
            version: "0.1.47", identifier: "com.example.Something")
        let archive = scratch.appendingPathComponent("Softcap-0.1.47.zip")
        try zip(stranger, to: archive)
        let installed = try makeBundle(
            in: try subdirectory("Applications", of: scratch), version: "0.1.42")
        let before = try versionOfApp(at: installed)

        let installer = UpdateInstaller(
            downloader: FileOnDisk(file: archive),
            http: OneAnswer(body: "\(try Checksums.digest(ofFileAt: archive))  ./Softcap-0.1.47.zip")
        )

        let error = await #expect(throws: UpdateFailure.self) {
            try await installer.install(
                try release(version: "0.1.47"), replacing: installed) { _ in }
        }
        #expect(error?.kind == .unpackFailed)
        #expect(try versionOfApp(at: installed) == before)
    }

    /// A signature that no longer covers its code is refused — even when the
    /// checksums agree perfectly.
    ///
    /// This is the attack the signature step exists for, and it was passing it.
    /// Reading an identity is not checking it: `SecCodeCopySigningInformation`
    /// reports what the signature blob says, so a bundle with a replaced
    /// executable still names the team that signed the original. Whoever can
    /// publish the archive publishes the sums beside it, so the checksum agrees
    /// by construction — this test builds exactly that, hashing the archive
    /// *after* breaking the executable.
    @Test func abundleWhoseSignatureNoLongerCoversItIsRefused() async throws {
        let scratch = try scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let source = try makeBundle(
            in: try subdirectory("staging", of: scratch), version: "0.1.47", signed: true)

        // Broken after signing, which is what makes the seal wrong.
        let executable = source.appendingPathComponent("Contents/MacOS/Softcap")
        var bytes = try Data(contentsOf: executable)
        bytes[bytes.count / 2] ^= 0xFF
        try bytes.write(to: executable)

        let archive = scratch.appendingPathComponent("Softcap-0.1.47.zip")
        try zip(source, to: archive)

        let installed = try makeBundle(
            in: try subdirectory("Applications", of: scratch), version: "0.1.42", signed: true)
        let before = try versionOfApp(at: installed)

        let installer = UpdateInstaller(
            downloader: FileOnDisk(file: archive),
            http: OneAnswer(body: "\(try Checksums.digest(ofFileAt: archive))  ./Softcap-0.1.47.zip")
        )

        let error = await #expect(throws: UpdateFailure.self) {
            try await installer.install(
                try release(version: "0.1.47"), replacing: installed) { _ in }
        }
        #expect(error?.kind == .signatureChanged)
        #expect(try versionOfApp(at: installed) == before,
                "a bundle with a broken seal was installed anyway")
    }

    /// The other half, or the check above would pass by refusing everything: an
    /// intact bundle signed the same way still installs.
    @Test func asignedBundleThatIsWholeStillInstalls() async throws {
        let scratch = try scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let source = try makeBundle(
            in: try subdirectory("staging", of: scratch), version: "0.1.47", signed: true)
        let archive = scratch.appendingPathComponent("Softcap-0.1.47.zip")
        try zip(source, to: archive)
        let installed = try makeBundle(
            in: try subdirectory("Applications", of: scratch), version: "0.1.42", signed: true)

        let installer = UpdateInstaller(
            downloader: FileOnDisk(file: archive),
            http: OneAnswer(body: "\(try Checksums.digest(ofFileAt: archive))  ./Softcap-0.1.47.zip")
        )
        try await installer.install(
            try release(version: "0.1.47"), replacing: installed) { _ in }

        #expect(try versionOfApp(at: installed).contains("0.1.47"))
    }

    /// The version in the archive has to be the one the release claimed, or the
    /// app would go on reporting a number nobody published.
    @Test func anarchiveHoldingAdifferentVersionIsRefused() async throws {
        let scratch = try scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let source = try makeBundle(in: try subdirectory("staging", of: scratch), version: "0.1.99")
        let archive = scratch.appendingPathComponent("Softcap-0.1.47.zip")
        try zip(source, to: archive)
        let installed = try makeBundle(
            in: try subdirectory("Applications", of: scratch), version: "0.1.42")

        let installer = UpdateInstaller(
            downloader: FileOnDisk(file: archive),
            http: OneAnswer(body: "\(try Checksums.digest(ofFileAt: archive))  ./Softcap-0.1.47.zip")
        )

        let error = await #expect(throws: UpdateFailure.self) {
            try await installer.install(
                try release(version: "0.1.47"), replacing: installed) { _ in }
        }
        #expect(error?.kind == .unpackFailed)
    }

    // MARK: - asking before downloading anything

    /// The copy that is running is not always still on disk.
    ///
    /// Read off a machine: the app had been launched from a build directory
    /// that a later build removed, so `Bundle.main.bundleURL` named a path
    /// holding nothing. The install ran the whole download, the checksum and
    /// the signature check before the copy beside that path failed — under the
    /// one sentence `.notWritable` has, which told the reader to move Softcap
    /// into Applications. It was not where it was installed that was wrong.
    @Test func acopyThatIsNoLongerOnDiskIsSaidSoAndNothingIsDownloaded() async throws {
        let scratch = try scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let source = try makeBundle(in: try subdirectory("staging", of: scratch), version: "0.1.47")
        let archive = scratch.appendingPathComponent("Softcap-0.1.47.zip")
        try zip(source, to: archive)

        // Launched from here and then gone from here: the directory holding it
        // is removed, which is what a rebuild does to the bundle underneath.
        let vanished = try subdirectory("Products", of: scratch)
        let installed = try makeBundle(in: vanished, version: "0.1.42")
        try FileManager.default.removeItem(at: vanished)

        let handedOver = Handed()
        let installer = UpdateInstaller(
            downloader: FileOnDisk(file: archive, remember: handedOver),
            http: OneAnswer(body: "\(try Checksums.digest(ofFileAt: archive))  ./Softcap-0.1.47.zip")
        )

        let error = await #expect(throws: UpdateFailure.self) {
            try await installer.install(
                try release(version: "0.1.47"), replacing: installed) { _ in }
        }
        #expect(error?.kind == .bundleGone)
        #expect(handedOver.path == nil,
                "the archive was fetched before anyone asked where it would go")
    }

    /// The same question, asked of a place that is there and cannot be written:
    /// a disk image is mounted read-only, and an app run straight from one is
    /// where this is met outside a test. Here the sentence about moving it to
    /// Applications is the right one — and it is worth more before ten
    /// megabytes than after them.
    @Test func aplaceThatCannotBeWrittenIsRefusedBeforeTheDownload() async throws {
        let scratch = try scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let source = try makeBundle(in: try subdirectory("staging", of: scratch), version: "0.1.47")
        let archive = scratch.appendingPathComponent("Softcap-0.1.47.zip")
        try zip(source, to: archive)

        let readOnly = try subdirectory("Volumes", of: scratch)
        let installed = try makeBundle(in: readOnly, version: "0.1.42")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500], ofItemAtPath: readOnly.path)
        // Restored before the directory is thrown away: a read-only parent
        // cannot have its contents removed either, and the scratch would stay.
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: readOnly.path)
        }

        let handedOver = Handed()
        let installer = UpdateInstaller(
            downloader: FileOnDisk(file: archive, remember: handedOver),
            http: OneAnswer(body: "\(try Checksums.digest(ofFileAt: archive))  ./Softcap-0.1.47.zip")
        )

        let error = await #expect(throws: UpdateFailure.self) {
            try await installer.install(
                try release(version: "0.1.47"), replacing: installed) { _ in }
        }
        #expect(error?.kind == .notWritable)
        #expect(handedOver.path == nil,
                "the archive was fetched before anyone asked where it would go")
    }

    /// The downloaded archive is gone once the install has finished.
    ///
    /// It is the megabytes, and it is the one with a seam to hold on to: the
    /// stub hands back a path this test chose, so it can look at exactly the
    /// file the installer was given. A first attempt compared listings of the
    /// temporary directory before and after, and failed — the suite runs in
    /// parallel and the listing was full of other tests' working directories.
    /// A check that cannot tell its own leavings from somebody else's is not
    /// checking anything.
    @Test func theDownloadedArchiveIsNotLeftBehind() async throws {
        let scratch = try scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let source = try makeBundle(in: try subdirectory("staging", of: scratch), version: "0.1.47")
        let archive = scratch.appendingPathComponent("Softcap-0.1.47.zip")
        try zip(source, to: archive)
        let installed = try makeBundle(
            in: try subdirectory("Applications", of: scratch), version: "0.1.42")

        let handedOver = Handed()
        let installer = UpdateInstaller(
            downloader: FileOnDisk(file: archive, remember: handedOver),
            http: OneAnswer(body: "\(try Checksums.digest(ofFileAt: archive))  ./Softcap-0.1.47.zip")
        )
        try await installer.install(
            try release(version: "0.1.47"), replacing: installed) { _ in }

        let given = try #require(handedOver.path, "the downloader was never asked for the archive")
        #expect(!FileManager.default.fileExists(atPath: given.path),
                "the install left its copy of the archive in the temporary directory")
    }

    /// What the stub handed over, so the test can look for it afterwards.
    private final class Handed: @unchecked Sendable {
        private let lock = NSLock()
        private var url: URL?

        func record(_ value: URL) { lock.lock(); url = value; lock.unlock() }

        var path: URL? {
            lock.lock(); defer { lock.unlock() }
            return url
        }
    }

    /// The callback arrives from whatever queue the download is on.
    private final class Phases: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [String] = []

        func record(_ phase: UpdateInstaller.Phase) {
            let name = switch phase {
            case .downloading: "downloading"
            case .verifying:   "verifying"
            case .installing:  "installing"
            }
            lock.lock()
            if seen.last != name { seen.append(name) }
            lock.unlock()
        }

        var named: [String] {
            lock.lock(); defer { lock.unlock() }
            return seen
        }
    }
}

/// The relaunch runs through a shell, and a path is not a shell word.
@Suite struct PathsSurviveTheShell {

    @Test func aspaceDoesNotEndTheArgument() {
        #expect("/Applications/My Apps/Softcap.app".singleQuotedForShell
                == "'/Applications/My Apps/Softcap.app'")
    }

    /// The one character single quotes cannot carry. A folder named after
    /// somebody is enough to meet it.
    @Test func anapostropheIsEscaped() {
        #expect("/Users/o'brien/Softcap.app".singleQuotedForShell
                == "'/Users/o'\\''brien/Softcap.app'")
    }

    @Test func nothingElseIsTouched() {
        #expect("/Applications/Softcap.app".singleQuotedForShell
                == "'/Applications/Softcap.app'")
    }
}

/// What the installer does when the network says no rather than going quiet.
@Suite struct AnAnswerThatSaysNoIsNotTampering {

    private struct FileOnDisk: FileDownloader {
        let file: URL
        func download(
            _ url: URL, progress: @escaping @Sendable (Double) -> Void
        ) async throws -> URL {
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("softcap-test-\(UUID().uuidString)")
            try FileManager.default.copyItem(at: file, to: copy)
            progress(1)
            return copy
        }
    }

    private struct Refuses: HTTPClient {
        let status: Int
        func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
            (Data("<html>no</html>".utf8), status)
        }
        func post(
            _ url: URL, headers: [String: String], body: Data
        ) async throws -> (Data, Int) {
            (Data(), 405)
        }
    }

    /// The sums are fetched separately, and a fetch that fails is not the sums
    /// disagreeing. Both were reported as a mismatch, so an outage or a rate
    /// limit told the reader their download had been tampered with — an
    /// accusation, for a server having a bad afternoon.
    @Test func checksumsThatCannotBeFetchedAreAnetworkFailure() async throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("softcap-refuse-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let archive = scratch.appendingPathComponent("Softcap-0.1.47.zip")
        try Data(repeating: 1, count: 32).write(to: archive)
        let installed = scratch.appendingPathComponent("Softcap.app")
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)

        let base = "https://github.com/milushov/softcap/releases/download/v0.1.47"
        let release = Release(
            version: try #require(ReleaseVersion("0.1.47")),
            notes: "", archive: URL(string: "\(base)/Softcap-0.1.47.zip")!,
            archiveName: "Softcap-0.1.47.zip",
            checksums: URL(string: "\(base)/SHA256SUMS.txt")!,
            page: URL(string: "https://github.com/milushov/softcap/releases/latest")!
        )

        for status in [403, 404, 500, 503] {
            let installer = UpdateInstaller(
                downloader: FileOnDisk(file: archive), http: Refuses(status: status))
            let error = await #expect(throws: UpdateFailure.self) {
                try await installer.install(release, replacing: installed) { _ in }
            }
            #expect(error?.kind == .network, "a \(status) was reported as tampering")
            #expect(error?.diagnostic.contains("\(status)") == true,
                    "the log does not say which status came back")
        }
    }
}

/// Who may replace whom, as the rule rather than as a bundle.
///
/// The bundles cannot ask this question here: a test can sign ad-hoc, which
/// identifies nobody, and has no certificate to sign the other side with. The
/// policy is a function over the two identities for exactly that reason, and
/// this is the whole of its truth table.
@Suite struct WhoMayReplaceWhom {

    @Test func anonymousStaysAcceptableToAnonymous() {
        #expect(UpdateInstaller.identityMayChange(from: nil, to: nil))
    }

    /// The transition this was written for: every copy installed so far is
    /// ad-hoc, and the first signed release has to be installable by them.
    @Test func anonymousAcceptsSomebodyIdentified() {
        #expect(UpdateInstaller.identityMayChange(from: nil, to: "A1B2C3D4E5"))
    }

    @Test func thesameTeamGoesOnReplacingItself() {
        #expect(UpdateInstaller.identityMayChange(from: "A1B2C3D4E5", to: "A1B2C3D4E5"))
    }

    /// The direction that loses something, and the one this check exists for.
    @Test func anidentifiedCopyRefusesAnanonymousOne() {
        #expect(!UpdateInstaller.identityMayChange(from: "A1B2C3D4E5", to: nil))
    }

    @Test func anidentifiedCopyRefusesAdifferentTeam() {
        #expect(!UpdateInstaller.identityMayChange(from: "A1B2C3D4E5", to: "F6G7H8I9J0"))
    }
}
