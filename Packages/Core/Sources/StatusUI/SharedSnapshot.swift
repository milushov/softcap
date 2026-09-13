import Foundation
import os
#if os(macOS)
import Security
#endif
import ProviderKit
import Preferences

/// The state snapshot the app shares with the widget.
///
/// A widget is a separate process on a tight time and memory budget: it may
/// neither read the app's keychain nor hold an OAuth session. So there stays one
/// source of truth — the app writes here after every poll, the widget only reads.
public struct SharedSnapshot: Codable, Sendable, Equatable {
    public let accounts: [AccountSnapshot]
    public let capturedAt: Date
    public let rowLayout: RowLayout
    public let showSnapshotAge: Bool
    public let languageCode: String?

    /// How often the app polls in the background, so the widget can tell a
    /// reading that is merely recent from one that is overdue. Optional because
    /// a snapshot written before this existed must still decode — a widget that
    /// fails to read the file shows "No accounts found", which is a lie about
    /// the accounts.
    public let pollingEvery: TimeInterval?

    /// Decoded field by field, each falling back to something usable.
    ///
    /// `pollingEvery` was made optional when it was added, so that a snapshot
    /// written by the previous build would still decode — a widget that cannot
    /// read the file shows "No accounts found", which is a lie about the
    /// accounts. That fixed the next field. This fixes the rest of them: a
    /// missing or malformed entry costs its own setting and not the reading.
    /// Consumes one array element of unknown shape.
    private struct SkippedRow: Decodable {
        init(from decoder: any Decoder) throws { _ = try decoder.singleValueContainer() }
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        // Row by row: one account that will not decode costs that row, not the
        // list. Decoding the array whole would answer a single bad entry with
        // "No accounts found", which is the sentence this whole decoder exists
        // to avoid saying untruthfully.
        if var rows = try? box.nestedUnkeyedContainer(forKey: .accounts) {
            var kept: [AccountSnapshot] = []
            while !rows.isAtEnd {
                if let row = try? rows.decode(AccountSnapshot.self) {
                    kept.append(row)
                } else {
                    _ = try? rows.decode(SkippedRow.self)
                }
            }
            accounts = kept
        } else {
            accounts = []
        }
        capturedAt = ((try? box.decodeIfPresent(Date.self, forKey: .capturedAt)) ?? nil)
            ?? Date(timeIntervalSince1970: 0)
        rowLayout = ((try? box.decodeIfPresent(RowLayout.self, forKey: .rowLayout)) ?? nil)
            ?? Preferences.defaults.rowLayout
        showSnapshotAge = ((try? box.decodeIfPresent(Bool.self, forKey: .showSnapshotAge)) ?? nil)
            ?? Preferences.defaults.showSnapshotAge
        languageCode = (try? box.decodeIfPresent(String.self, forKey: .languageCode)) ?? nil
        pollingEvery = (try? box.decodeIfPresent(TimeInterval.self, forKey: .pollingEvery)) ?? nil
    }

    public init(
        accounts: [AccountSnapshot],
        capturedAt: Date,
        rowLayout: RowLayout,
        showSnapshotAge: Bool,
        languageCode: String?,
        pollingEvery: TimeInterval? = nil
    ) {
        self.accounts = accounts
        self.capturedAt = capturedAt
        self.rowLayout = rowLayout
        self.showSnapshotAge = showSnapshotAge
        self.languageCode = languageCode
        self.pollingEvery = pollingEvery
    }
}

/// Snapshot exchange between the app and the widget.
///
/// An App Group container on both platforms. A plain path under `Application
/// Support` was tried first on macOS and does not work: a widget extension has
/// to be sandboxed there or the system never registers it, and a sandboxed
/// extension sees its own container instead of the app's path.
public enum SharedStore {
    private static let fileName = "snapshot.json"

    private static let log = Logger(subsystem: "app.softcap.Softcap", category: "SharedStore")

    /// The name every platform's group ends with. macOS prefixes it with the
    /// team identifier and iOS does not, so this is the common part rather than
    /// the whole answer.
    private static let baseGroup = "group.app.softcap"

    /// The app group identifier.
    ///
    /// On macOS it is read from the binary's own entitlements instead of being
    /// written down: the name needs the team prefix, and hard-coding that ties
    /// every build to one developer account. Xcode expands
    /// `$(TeamIdentifierPrefix)` in the entitlements file, and the binary is
    /// then asked what it was actually granted.
    ///
    /// iOS takes no prefix, and `SecTaskCopyValueForEntitlement` does not exist
    /// there — which is why this is two paths and not one.
    #if os(macOS)
    public static let appGroup: String = {
        guard let task = SecTaskCreateFromSelf(nil),
              let groups = SecTaskCopyValueForEntitlement(
                  task, "com.apple.security.application-groups" as CFString, nil
              ) as? [String],
              let group = groups.first(where: { $0.hasSuffix(baseGroup) })
        else { return baseGroup }
        return group
    }()
    #else
    public static let appGroup = baseGroup
    #endif

    /// A file rather than `UserDefaults`: a snapshot may hold a dozen accounts,
    /// while shared defaults are meant for small values.
    ///
    /// `nil` when the group container is unavailable — which on a local build
    /// means the entitlement is missing or the profile does not carry the
    /// group.
    public static var url: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        else {
            // Worth saying out loud. The usual cause is a build with no signing
            // identity: `$(TeamIdentifierPrefix)` in the entitlements expands to
            // nothing, macOS is handed a group name without the team prefix and
            // grants no container. Everything else keeps working and the widget
            // stays empty for good, with nothing anywhere to explain it.
            log.error("no container for app group \(appGroup, privacy: .public) — the widget will stay empty")
            return nil
        }

        return container.appendingPathComponent(fileName)
    }

    /// The app's own directory, which needs no app group and therefore no
    /// permission from anybody.
    ///
    /// The group container is shared with the widget, and macOS guards a group
    /// container as "data from other apps" whenever the signature cannot prove
    /// the app belongs to the team the group is filed under — which an ad-hoc
    /// signature never can. Reaching it at startup is what put that prompt in
    /// front of every reader, on every update, before anything had been drawn.
    ///
    /// Only the widget needs the shared copy. Everything the app reads for
    /// itself — the history behind the statistics screen, and the snapshot the
    /// threshold tracker restores its baseline from — lives here instead.
    public static var localURL: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else {
            log.error("no application support directory — history will not be kept")
            return nil
        }
        return base
            .appendingPathComponent("app.softcap.Softcap", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// Where the usage history lives: beside the app's own snapshot, its own
    /// file. The snapshot is rewritten whole on every poll; a month of readings
    /// must not be.
    public static var historyURL: URL? {
        localURL?.deletingLastPathComponent().appendingPathComponent("history.json")
    }

    /// Writes the copy the widget reads. Costs a look into the group container,
    /// so the caller decides whether a widget is on screen to read it.
    public static func write(_ snapshot: SharedSnapshot) {
        guard let url else { return }
        write(snapshot, to: url)
    }

    /// `nil` when the app has never run or the path is unavailable.
    public static func read() -> SharedSnapshot? {
        guard let url else { return nil }
        return read(from: url)
    }

    /// The app's own copy — written on every poll, read at startup.
    public static func writeLocal(_ snapshot: SharedSnapshot) {
        guard let localURL else { return }
        write(snapshot, to: localURL)
    }

    public static func readLocal() -> SharedSnapshot? {
        guard let localURL else { return nil }
        return read(from: localURL)
    }

    /// Writing and reading take an explicit location as well, so the exchange
    /// can be exercised without touching the real container: a test that wrote
    /// to `Application Support` would leave traces on the machine running it.
    public static func write(_ snapshot: SharedSnapshot, to url: URL) {
        let data: Data
        do {
            data = try JSONEncoder().encode(snapshot)
        } catch {
            // The line below reports a failed write for exactly this reason, and
            // a failed encode has the same symptom: a widget quietly showing
            // yesterday's numbers. It was the one step of the two that said
            // nothing.
            log.error("snapshot not encoded: \(error.localizedDescription, privacy: .public)")
            return
        }

        do {
            // An atomic write needs the directory to already be there.
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            // Atomic: the widget may read while the app writes, and a
            // half-written file would decode to nothing — an empty widget
            // instead of stale data.
            try data.write(to: url, options: .atomic)
        } catch {
            // Reported rather than swallowed: the whole symptom of a failed
            // write is a widget quietly showing yesterday's numbers.
            log.error("snapshot not written: \(error.localizedDescription, privacy: .public)")
        }
    }

    public static func read(from url: URL) -> SharedSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SharedSnapshot.self, from: data)
    }
}
