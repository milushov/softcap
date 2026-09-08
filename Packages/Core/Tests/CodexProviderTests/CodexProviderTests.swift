import Testing
import Foundation
import ProviderKit
@testable import CodexProvider

private struct StubFS: CodexFileSystem {
    var auth: Data?
    var lines: [String]
    /// Session files as they would be found on disk, oldest first.
    var history: [[String]] = []
    var authError: (any Error)?
    var linesError: (any Error)?

    func readAuthJSON() throws -> Data {
        if let authError { throw authError }
        guard let auth else {
            throw ProviderFailure(kind: .noData, diagnostic: "no auth.json")
        }
        return auth
    }

    func sessionLines(since: Date) throws -> [[String]] {
        if let linesError { throw linesError }
        return history
    }

    func latestSessionLines() throws -> [String] {
        if let linesError { throw linesError }
        return lines
    }
}

private func authFixture() -> Data {
    let payload: [String: Any] = [
        "name": "Tyler Durden",
        "https://api.openai.com/auth": [
            "chatgpt_plan_type": "plus", "chatgpt_account_id": "acc-1",
        ],
    ]
    let body = try! JSONSerialization.data(withJSONObject: payload)
    let seg = body.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    let json: [String: Any] = ["tokens": ["id_token": "h.\(seg).s"]]
    return try! JSONSerialization.data(withJSONObject: json)
}

private let limitsLine = """
{"timestamp":"2026-08-27T16:47:37.701Z","type":"event_msg","payload":\
{"type":"token_count","rate_limits":{"limit_id":"codex","plan_type":"plus",\
"primary":{"used_percent":12.0,"window_minutes":300,"resets_at":1787867253},\
"secondary":{"used_percent":32.0,"window_minutes":10080,"resets_at":1788454053}}}}
"""

@Test func discoversOneAccountWhenAuthExists() async throws {
    let provider = CodexUsageProvider(fileSystem: StubFS(auth: authFixture(), lines: []))
    let refs = try await provider.discoverAccounts()
    #expect(refs.count == 1)
    #expect(refs[0].id == "codex/acc-1")
    #expect(refs[0].provider == .codex)
}

@Test func discoversNothingWhenNotLoggedIn() async throws {
    let provider = CodexUsageProvider(fileSystem: StubFS(auth: nil, lines: []))
    let refs = try await provider.discoverAccounts()
    #expect(refs.isEmpty)
}

@Test func buildsSnapshotMarkedAsSnapshotNotLive() async throws {
    let provider = CodexUsageProvider(fileSystem: StubFS(auth: authFixture(), lines: [limitsLine]))
    let ref = try await provider.discoverAccounts()[0]
    let snapshot = try await provider.fetch(ref)

    #expect(snapshot.provider == .codex)
    #expect(snapshot.displayName == "Tyler Durden")
    #expect(snapshot.planLabel == "Plus")
    #expect(snapshot.windows.count == 2)
    #expect(snapshot.failure == nil)
    #expect(snapshot.freshness.isStale == true)
    #expect(snapshot.freshness.capturedAt
            == CodexTimestamp.date(from: "2026-08-27T16:47:37.701Z"))
}

@Test func reportsNoDataAsFailureInsteadOfThrowingAway() async throws {
    let provider = CodexUsageProvider(fileSystem: StubFS(auth: authFixture(), lines: []))
    let ref = try await provider.discoverAccounts()[0]
    let snapshot = try await provider.fetch(ref)

    #expect(snapshot.failure?.kind == .noData)
    #expect(snapshot.windows.isEmpty)
    #expect(snapshot.displayName == "Tyler Durden")
}

/// Two different silences used to leave here as the same empty list: Codex not
/// being set up, and Codex being set up with a file that will not parse. The
/// first is nothing to report. The second is a row that disappears, for a file
/// whose shape belongs to somebody else — and an upstream change of shape has
/// caught this project out before.
@Suite struct TellingTheTwoSilencesApart {

    private struct NoAuth: CodexFileSystem {
        func readAuthJSON() throws -> Data {
            throw ProviderFailure(kind: .noData, diagnostic: "no auth.json")
        }
        func latestSessionLines() throws -> [String] { [] }
        func sessionLines(since: Date) throws -> [[String]] { [] }
    }

    private struct BrokenAuth: CodexFileSystem {
        func readAuthJSON() throws -> Data { Data(#"{"tokens":{}}"#.utf8) }
        func latestSessionLines() throws -> [String] { [] }
        func sessionLines(since: Date) throws -> [[String]] { [] }
    }

    @Test func noFileMeansNothingToShow() async throws {
        let provider = CodexUsageProvider(fileSystem: NoAuth())
        let refs = try await provider.discoverAccounts()
        #expect(refs.isEmpty, "Codex is not set up here; an empty list is the honest answer")
    }

    @Test func aFileThatWillNotParseIsReported() async {
        let provider = CodexUsageProvider(fileSystem: BrokenAuth())
        await #expect(throws: ProviderFailure.self) {
            _ = try await provider.discoverAccounts()
        }
    }
}
