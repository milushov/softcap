import Foundation
import ProviderKit

/// File access is behind a protocol so tests never touch the disk.
public protocol CodexFileSystem: Sendable {
    func readAuthJSON() throws -> Data
    func latestSessionLines() throws -> [String]
    /// Every session file changed since the given moment, newest last. Used to
    /// recover the history Codex already wrote before this app was watching.
    func sessionLines(since: Date) throws -> [[String]]
}

/// Reads the real `~/.codex` directory.
///
/// macOS only: iOS has neither a home directory in this sense nor Codex session
/// files. On iOS the data arrives as a snapshot prepared by the Mac, which is
/// why the parsing above is shared while this reader is not.
#if os(macOS)
public struct RealCodexFileSystem: CodexFileSystem {
    private let root: URL

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser
                              .appendingPathComponent(".codex")) {
        self.root = root
    }

    public func readAuthJSON() throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("auth.json"))
    }

    /// Takes the newest session file. Newest by modification time: Codex appends
    /// events to the end of the active file.
    public func latestSessionLines() throws -> [String] {
        let sessions = root.appendingPathComponent("sessions")
        guard let walker = FileManager.default.enumerator(
            at: sessions,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
        ) else {
            throw ProviderFailure(kind: .noData, diagnostic: "codex sessions directory missing")
        }

        var newest: (url: URL, modified: Date)?
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            guard let modified = values?.contentModificationDate else { continue }
            if newest == nil || modified > newest!.modified { newest = (url, modified) }
        }

        guard let file = newest?.url else {
            throw ProviderFailure(kind: .noData, diagnostic: "no codex session files")
        }
        let text = try String(contentsOf: file, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    public func sessionLines(since: Date) throws -> [[String]] {
        let sessions = root.appendingPathComponent("sessions")
        guard let walker = FileManager.default.enumerator(
            at: sessions,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
        ) else {
            throw ProviderFailure(kind: .noData, diagnostic: "codex sessions directory missing")
        }

        var found: [(url: URL, modified: Date)] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            guard let modified = values?.contentModificationDate, modified >= since else { continue }
            found.append((url, modified))
        }

        return found
            .sorted { $0.modified < $1.modified }
            .compactMap { try? String(contentsOf: $0.url, encoding: .utf8) }
            .map { $0.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) }
    }
}

#endif

public struct CodexUsageProvider: UsageProvider {
    public let id: ProviderID = .codex
    private let fileSystem: any CodexFileSystem
    private let excludedAccountIDs: Set<String>

    #if os(macOS)
    public init(
        fileSystem: any CodexFileSystem = RealCodexFileSystem(),
        excludedAccountIDs: Set<String> = []
    ) {
        self.fileSystem = fileSystem
        self.excludedAccountIDs = excludedAccountIDs
    }
    #else
    /// On iOS there is no default source: the caller supplies one, or the
    /// provider is simply not used.
    public init(fileSystem: any CodexFileSystem, excludedAccountIDs: Set<String> = []) {
        self.fileSystem = fileSystem
        self.excludedAccountIDs = excludedAccountIDs
    }
    #endif

    /// The one Codex account, or none.
    ///
    /// Two different silences used to come out of here as the same empty list.
    /// No `auth.json` means Codex is not set up on this machine, and showing
    /// nothing is right. An `auth.json` that will not parse means it is set up
    /// and something is wrong — and the row disappearing is the worst way to say
    /// that, especially for a file whose shape belongs to somebody else. This
    /// project has already been caught out once by an upstream change of shape.
    public func discoverAccounts() async throws -> [AccountRef] {
        guard let data = try? fileSystem.readAuthJSON() else { return [] }
        let identity = try CodexIdentityReader.parse(authJSON: data)
        guard !excludedAccountIDs.contains("codex/\(identity.accountID)") else { return [] }
        return [AccountRef(
            id: "codex/\(identity.accountID)", provider: .codex, handle: identity.accountID,
            lastKnownName: identity.displayName
        )]
    }

    /// A read failure is not thrown outward: the account still belongs in the
    /// list, just marked as having no data.
    public func fetch(_ ref: AccountRef) async throws -> AccountSnapshot {
        let identity = try CodexIdentityReader.parse(authJSON: try fileSystem.readAuthJSON())
        guard ref.id == "codex/\(identity.accountID)" else {
            throw ProviderFailure(kind: .noData, diagnostic: "local codex account changed during read")
        }
        let plan = identity.planType.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "—"

        do {
            let lines = try fileSystem.latestSessionLines()
            let event = try RolloutParser.latestEvent(inLines: lines)
            return AccountSnapshot(
                id: ref.id, provider: .codex,
                displayName: identity.displayName,
                planLabel: event.planType.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? plan,
                windows: event.windows,
                freshness: .snapshot(event.capturedAt),
                failure: nil
            )
        } catch {
            let failure = error as? ProviderFailure
                ?? ProviderFailure(kind: .noData, diagnostic: "codex data unavailable")
            return AccountSnapshot(
                id: ref.id, provider: .codex,
                displayName: identity.displayName, planLabel: plan,
                windows: [], freshness: .snapshot(.distantPast), failure: failure
            )
        }
    }
}
