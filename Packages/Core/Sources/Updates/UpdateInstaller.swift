import Foundation
import ProviderKit

// Everything below is the Mac's.
//
// `Process` is not on iOS at all, and `SecStaticCode` lives only in the macOS
// SDK — `Security` itself exists on both, so an import check cannot see this.
// The package declares .iOS(.v17) and exports `Updates` as a library, so
// without this guard the first person to add it to the phone target, or to
// build the package for a simulator, meets a raw compile error where
// `CoreStaysPortable` promises a named three-second failure.
//
// The pure half of the module — versions, checksums, the schedule, the feed —
// is portable and sits outside this guard, in its own files.
#if os(macOS)
import Security

/// Downloading a release and putting it where the running app is.
///
/// Each step is a refusal rather than a workaround. What is installed is what
/// the release published, is this app, and is the version it said it was —
/// because nothing downstream will ask again: `URLSession` does not mark a file
/// with `com.apple.quarantine` the way a browser does, so Gatekeeper never sees
/// it. That absence is the feature — an update that opens without the dialog an
/// ad-hoc signed build otherwise gets — and it is also why these checks are the
/// only ones there are.
public struct UpdateInstaller: Sendable {

    public enum Phase: Sendable, Equatable {
        case downloading(Double)
        case verifying
        case installing
    }

    public static let bundleIdentifier = "app.softcap.Softcap"

    private let downloader: any FileDownloader
    private let http: any HTTPClient

    public init(downloader: any FileDownloader, http: any HTTPClient) {
        self.downloader = downloader
        self.http = http
    }

    /// Replaces the bundle at `bundle` with the build `release` publishes.
    ///
    /// Does not restart: `restart(_:)` is separate so that a test can install
    /// without relaunching anything.
    public func install(
        _ release: Release,
        replacing bundle: URL,
        progress: @escaping @Sendable (Phase) -> Void
    ) async throws {
        // Asked first, and asked of the place rather than of the download.
        // Whether this copy can be replaced does not depend on a single byte
        // arriving, and finding out after ten megabytes is both a wasted
        // download and an answer given too late to be read as the cause.
        try checkReplaceable(bundle)

        let work = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: work) }

        let download = release.download

        progress(.downloading(0))
        let archive: URL
        do {
            archive = try await downloader.download(download.archive) {
                progress(.downloading($0))
            }
        } catch {
            throw Self.networkFailure(error)
        }
        defer { try? FileManager.default.removeItem(at: archive) }

        progress(.verifying)
        try await verify(archive, of: download)

        let unpacked = try unpack(archive, into: work)
        try check(unpacked, isSoftcapAt: release.version)
        try checkSigningIdentity(of: unpacked, matches: bundle)

        progress(.installing)
        try replace(bundle, with: unpacked)
    }

    // MARK: - verifying

    private func verify(_ archive: URL, of download: Release.Download) async throws {
        let published: Checksums
        do {
            let (data, status) = try await http.get(download.checksums, headers: [:])
            // Not reaching the sums is not the same as the sums disagreeing.
            // Both were reported as a mismatch, so an outage or a rate limit
            // told the reader their download had been tampered with.
            guard status == 200 else {
                throw UpdateFailure(kind: .network,
                                    diagnostic: "checksums came back \(status)")
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw UpdateFailure(kind: .network, diagnostic: "checksums were not text")
            }
            published = Checksums(text)
        } catch let failure as UpdateFailure {
            throw failure
        } catch {
            throw Self.networkFailure(error)
        }

        guard let expected = published.digest(for: download.archiveName) else {
            throw UpdateFailure(kind: .checksumMismatch,
                                diagnostic: "no line for \(download.archiveName)")
        }

        let actual = try Checksums.digest(ofFileAt: archive)
        guard actual == expected else {
            throw UpdateFailure(
                kind: .checksumMismatch,
                diagnostic: "got \(actual.prefix(12)), expected \(expected.prefix(12))")
        }
    }

    // MARK: - unpacking

    /// `ditto`, not `unzip`: it is the only one that keeps a bundle's symlinks
    /// and its signature intact, and it is what built the archive in the first
    /// place.
    private func unpack(_ archive: URL, into directory: URL) throws -> URL {
        let out = directory.appendingPathComponent("unpacked")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, out.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw UpdateFailure(kind: .unpackFailed, diagnostic: "ditto would not run")
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateFailure(kind: .unpackFailed,
                                diagnostic: "ditto exited \(process.terminationStatus)")
        }

        // Exactly one, not the first one found. `contentsOfDirectory` answers in
        // whatever order the file system holds, which on APFS is a hash of the
        // name — so an archive carrying a second bundle could decide which one
        // was installed by choosing what to call it.
        let bundles = try FileManager.default
            .contentsOfDirectory(at: out, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "app" }
        guard bundles.count == 1, let app = bundles.first else {
            throw UpdateFailure(kind: .unpackFailed,
                                diagnostic: "\(bundles.count) bundles in the archive")
        }
        return app
    }

    /// A matching checksum says the bytes are the ones published. It does not
    /// say they are the right ones — a release that shipped the wrong artefact
    /// would checksum perfectly.
    private func check(_ bundle: URL, isSoftcapAt version: ReleaseVersion) throws {
        let plist = bundle.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist) as? [String: Any] else {
            throw UpdateFailure(kind: .unpackFailed, diagnostic: "no Info.plist")
        }
        guard info["CFBundleIdentifier"] as? String == Self.bundleIdentifier else {
            throw UpdateFailure(kind: .unpackFailed, diagnostic: "another app's bundle")
        }
        let found = (info["CFBundleShortVersionString"] as? String).flatMap(ReleaseVersion.init)
        guard let found, found == version else {
            throw UpdateFailure(
                kind: .unpackFailed,
                diagnostic: "the archive holds \(found?.description ?? "no version")")
        }
    }

    /// The check meant to notice a swapped bundle.
    ///
    /// Two questions, and the first one was missing. **Does the signature still
    /// cover the code**, and **is it the same signer**. Only the second was
    /// asked, and asking it alone answered nothing: reading an identity is not
    /// checking it — `SecCodeCopySigningInformation` parses the signature blob
    /// and reports what it says, so a bundle whose executable has been replaced
    /// still names the team that signed the original. Every release is signed,
    /// ad-hoc when no certificate is configured, so the first question can be
    /// put to all of them.
    ///
    /// Nothing is demanded of the arriving bundle that the installed one cannot
    /// answer for itself: an app whose own signature is broken is in no position
    /// to insist.
    private func checkSigningIdentity(of new: URL, matches current: URL) throws {
        guard Self.signatureIsIntact(of: current) else { return }

        guard Self.signatureIsIntact(of: new) else {
            throw UpdateFailure(kind: .signatureChanged,
                                diagnostic: "the arriving signature does not cover its code")
        }

        let running = Self.teamIdentifier(of: current)
        let arriving = Self.teamIdentifier(of: new)
        guard Self.identityMayChange(
            from: running, to: arriving, whenRunningIsAnonymous: Self.isAdHoc(current)
        ) else {
            throw UpdateFailure(kind: .signatureChanged,
                                diagnostic: "signed by \(arriving ?? "nobody")")
        }
    }

    /// Whether the arriving identity may stand in for the running one.
    ///
    /// The same team, always. And **anything at all in place of nobody**: an
    /// ad-hoc copy has no identity to lose, so nothing is given up by taking a
    /// signed one. This direction was refused until now, and the cost of that
    /// was written down before it could be paid — every installed copy is
    /// ad-hoc, so the first release carrying a certificate would have been
    /// turned away by all of them at once, each sending somebody to the release
    /// page to do by hand what this exists to do.
    ///
    /// It gives up nothing because there was nothing there. Whoever could put a
    /// signed bundle in the way of this download could put an ad-hoc one there
    /// instead, and that has always been accepted for an ad-hoc install. What
    /// stays refused is every direction that loses something: an identified copy
    /// replaced by an anonymous one, or by another team's.
    ///
    /// Anonymity is a fact about the signature, not about a missing name. The
    /// first version of this read "no team identifier" as "ad-hoc", and a team
    /// is also absent from a signature this process could not parse and from a
    /// certificate that carries no team at all — somebody who re-signed their
    /// own copy locally would have had the guard quietly dropped for them, and
    /// taken the next bundle from anybody.
    static func identityMayChange(
        from running: String?, to arriving: String?, whenRunningIsAnonymous anonymous: Bool
    ) -> Bool {
        anonymous || running == arriving
    }

    /// Whether the signature is ad-hoc — sealed, and identifying nobody.
    static func isAdHoc(_ bundle: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess,
              let code else { return false }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
                  code, SecCSFlags(rawValue: kSecCSSigningInformation), &information
              ) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let flags = dictionary[kSecCodeInfoFlags as String] as? UInt32
        else { return false }
        return SecCodeSignatureFlags(rawValue: flags).contains(.adhoc)
    }

    /// Whether the signature still matches what it covers.
    ///
    /// This is the one that catches a patched executable, and it is what
    /// `codesign --verify` runs. An ad-hoc signature answers it as well as a
    /// Developer ID one does — it identifies nobody, but it still seals the
    /// bundle it was made from.
    static func signatureIsIntact(of bundle: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess,
              let code else { return false }
        return SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess
    }

    /// Who signed it, for a signature already known to be intact. `nil` for an
    /// ad-hoc one, which identifies nobody.
    static func teamIdentifier(of bundle: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess,
              let code else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
                  code, SecCSFlags(rawValue: kSecCSSigningInformation), &information
              ) == errSecSuccess,
              let dictionary = information as? [String: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }

    // MARK: - replacing

    /// Whether there is still something here to replace, and room beside it to
    /// stage the replacement.
    ///
    /// Two different situations were one sentence. A bundle that is **gone** —
    /// launched from a directory a rebuild removed, or moved to the Trash while
    /// it ran — was reported as a place that could not be written, under advice
    /// to move Softcap into Applications; there was nothing left to move. A
    /// bundle that is **there and read-only** — an app run straight from the
    /// mounted disk image is the one that happens to people — is the case that
    /// advice was written for, and it still gets it.
    ///
    /// The probe is a real write, not `isWritableFile(atPath:)`, which answers
    /// from the permission bits and does not know about a read-only mount, an
    /// ACL, or the sandbox. This module already has one check that read what a
    /// signature claimed instead of verifying it; the answer here is the one
    /// `replaceItemAt` will get.
    private func checkReplaceable(_ bundle: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: bundle.path) else {
            throw UpdateFailure(kind: .bundleGone,
                                diagnostic: "nothing at the path this copy was launched from")
        }

        // One name, not a fresh one each time. Nothing here can promise the
        // removal below happens — the process can be killed between the two
        // lines, and the unlink can fail on its own — and a probe named after a
        // new UUID every attempt turns that into a pile of hidden files in
        // `/Applications`. Named once, the worst case is a single empty file
        // that the next attempt overwrites and clears.
        let probe = bundle.deletingLastPathComponent()
            .appendingPathComponent(".softcap-update-probe")
        do {
            // `.atomic` writes a neighbour and renames it, which is the pair of
            // operations `replace(_:with:)` needs the directory to allow.
            try Data().write(to: probe, options: .atomic)
        } catch {
            // The reason, not just the refusal: a read-only mount and a full
            // disk are the same sentence on screen and different things to do
            // about it, and the log is where that difference can live.
            throw UpdateFailure(
                kind: .notWritable,
                diagnostic: "nothing can be written beside the installed app: \(error)")
        }
        try? fileManager.removeItem(at: probe)
    }

    /// Atomic on APFS: the old bundle is kept until the new one is in place, and
    /// a failure leaves what was there.
    ///
    /// The copy is staged beside the installed app rather than left in the
    /// temporary directory, because `replaceItemAt` is only atomic within a
    /// volume — and a bundle half-moved across one is where an app that will not
    /// launch comes from.
    private func replace(_ current: URL, with new: URL) throws {
        let fileManager = FileManager.default
        let staged = current.deletingLastPathComponent()
            .appendingPathComponent(".\(current.lastPathComponent).incoming")

        try? fileManager.removeItem(at: staged)
        do {
            try fileManager.copyItem(at: new, to: staged)
        } catch {
            throw UpdateFailure(kind: .notWritable,
                                diagnostic: "could not write beside the installed app")
        }

        do {
            _ = try fileManager.replaceItemAt(current, withItemAt: staged)
        } catch {
            try? fileManager.removeItem(at: staged)
            throw UpdateFailure(kind: .notWritable, diagnostic: "could not replace the app")
        }
    }

    // MARK: - restarting

    /// Quits and comes back.
    ///
    /// The wait is not decoration: `open` on a bundle whose app is still running
    /// activates the copy already in memory rather than launching the new one,
    /// and the update would appear not to have happened until the next launch.
    @discardableResult
    public static func restart(_ bundle: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; "
                + "/usr/bin/open \(bundle.path.singleQuotedForShell)",
        ]
        // Whether the watcher was started at all decides whether quitting is
        // the right next move: the caller logged "restarting" and terminated
        // regardless, so a failed spawn left the new version installed and the
        // app simply gone.
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    // MARK: -

    private func scratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("softcap-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// A provider's failure, said in this module's words.
    private static func networkFailure(_ error: any Error) -> UpdateFailure {
        UpdateFailure(kind: .network,
                      diagnostic: (error as? ProviderFailure)?.diagnostic ?? "\(type(of: error))")
    }
}

extension String {
    /// A path is not a shell word: a space ends the argument and a quote ends
    /// the string. Single quotes carry everything except a single quote, which
    /// is closed, escaped, and reopened.
    public var singleQuotedForShell: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

#endif
