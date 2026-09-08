import Testing
import Foundation

/// Everything `deploy.sh` verifies runs after the files are already live. That is
/// unavoidable — the check is that the *served* bytes are right — but it means a
/// deploy that fails its own verification leaves the broken page up. It happened
/// once, when a digest check found six mismatches after the transfer, and there
/// was no way back but forward.
///
/// So the version that was live is copied aside before anything is replaced. Two
/// lines of shell, easy to drop in a tidy-up, and nothing would notice until the
/// day it was needed.
@Suite struct TheDeployKeepsAWayBack {

    @Test func theLiveVersionIsKeptBeforeAnythingIsReplaced() throws {
        let script = try Self.deploy()

        guard let snapshot = script.range(of: "snapshot_current\n"),
              let ship = script.range(of: "rsync -az -e") else {
            Issue.record("the deploy no longer takes a snapshot, or no longer ships with rsync")
            return
        }
        #expect(snapshot.lowerBound < ship.lowerBound, """
            the snapshot is taken after the files are replaced, which copies aside \
            the version that has just gone live rather than the one it replaced
            """)
    }

    /// Restoring a snapshot that is missing files would take the site down, which
    /// is worse than the broken page it is meant to repair.
    @Test func rollingBackRefusesAnIncompleteSnapshot() throws {
        let script = try Self.deploy()
        let body = try Self.body(of: "roll_back()", in: script)

        #expect(body.contains("prev/dist"), "the rollback does not read the snapshot")
        // The comparison itself, not a mention of it. Written as `contains` of the
        // bare `${#SERVED[@]}` this passed with the floor removed, because the
        // refusal message names the same count two lines further down.
        #expect(body.contains(#"-lt "${#SERVED[@]}""#), """
            the rollback does not compare what it holds against the number of files \
            the site serves
            """)
        #expect(body.contains("Nothing was changed"),
                "the rollback does not say that a refusal changed nothing")
    }

    /// The first version of this kept only `dist`, and the deploy ships the
    /// Caddyfile and the compose file too. A Caddyfile that does not parse stops
    /// the container — a site *down* rather than a site wrong — so the snapshot
    /// was missing the worse of the two failures it exists for.
    @Test func theSnapshotCoversWhatTheDeployReplaces() throws {
        let script = try Self.deploy()
        let taking = try Self.body(of: "snapshot_current()", in: script)
        let putting = try Self.body(of: "roll_back()", in: script)

        for file in ["Caddyfile", "docker-compose.yml"] {
            #expect(taking.contains(file), "the snapshot does not keep \(file)")
            #expect(putting.contains(file), "the rollback does not put \(file) back")
        }
        // Restoring two of three quietly would look exactly like restoring all of
        // them, which is the shape of failure this whole file is about.
        #expect(putting.contains("held no Caddyfile"),
                "the rollback does not say when the snapshot had no configuration in it")
    }

    /// After a rollback the live files are the previous version and are supposed
    /// to differ from this checkout, so the deploy's digest check is the wrong
    /// question to ask. A check that asked it would fail every time.
    @Test func rollingBackChecksTheSiteIsUpRatherThanUnchanged() throws {
        let body = try Self.body(of: "roll_back()", in: try Self.deploy())
        #expect(body.contains("</html>"), "the rollback does not check the page is whole")
        #expect(!body.contains("shasum -a 256 \"$HERE/$f\""), """
            the rollback compares the served files against this checkout, which \
            after a rollback they are meant not to match
            """)
    }

    @Test func theFailureNamesTheWayBack() throws {
        let script = try Self.deploy()
        #expect(script.contains("--rollback"), "nothing in the deploy offers a way back")
        guard let failure = script.range(of: "deploy did not land cleanly") else {
            Issue.record("the deploy no longer reports a failure by that name")
            return
        }
        let after = String(script[failure.upperBound...].prefix(240))
        #expect(after.contains("--rollback"), """
            the failure message does not name the rollback, so the way back exists \
            and is not offered at the moment it is needed
            """)
    }

    // MARK: -

    /// From a shell function's header to the line that closes it at column zero.
    private static func body(of declaration: String, in script: String) throws -> String {
        guard let start = script.range(of: declaration),
              let end = script.range(of: "\n}\n", range: start.upperBound..<script.endIndex)
        else { throw ScanIsLookingInTheWrongPlace(what: declaration, found: 0, least: 1) }
        return String(script[start.upperBound..<end.lowerBound])
    }

    private static func deploy() throws -> String {
        let text = try String(
            contentsOf: repositoryRoot.appendingPathComponent("site/deploy.sh"), encoding: .utf8)
        guard text.count > 8_000 else {
            throw ScanIsLookingInTheWrongPlace(what: "deploy.sh", found: text.count, least: 8_000)
        }
        return text
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
