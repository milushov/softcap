import Testing
import Foundation
import ProviderKit
import Preferences
@testable import StatusUI

/// "No accounts found" is a claim about the accounts, and the widget may only
/// make it when the app has actually said so.
///
/// `read` answered `nil` for three different situations — a file nobody has
/// written yet, a file this process is not allowed to open, and a file that is
/// not a snapshot at all — and the widget drew the same sentence for all three.
/// The middle one is the common one: an ad-hoc signature carries no team, macOS
/// then refuses the widget the group container, and somebody with four
/// subscriptions was told they had none.
@Suite struct TheWidgetTellsUnreadableFromEmpty {

    private static func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("reading-\(UUID().uuidString).json")
    }

    private static func snapshot(accounts: Int) -> SharedSnapshot {
        let now = Date(timeIntervalSince1970: 1_800_000)
        return SharedSnapshot(
            accounts: (0..<accounts).map { index in
                AccountSnapshot(
                    id: "claude/u-\(index)", provider: .claude,
                    displayName: "user\(index)@example.com", planLabel: "Max 20x",
                    windows: [LimitWindow(id: "session", percent: 40, resetsAt: nil)],
                    freshness: .live(now), failure: nil
                )
            },
            capturedAt: now, rowLayout: .twoWindows,
            showSnapshotAge: true, languageCode: nil
        )
    }

    @Test func aWrittenReadingComesBackWhole() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        SharedStore.write(Self.snapshot(accounts: 2), to: url)

        guard case .snapshot(let restored) = SharedStore.reading(from: url) else {
            Issue.record("a snapshot that was written did not read back as one")
            return
        }
        #expect(restored.accounts.count == 2)
    }

    /// The case the whole distinction exists to protect: the app looked, found
    /// nothing, and said so. That is the one reading "No accounts found" is
    /// entitled to, and it must not be confused with the others.
    @Test func aReadingOfNoAccountsIsStillAReading() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        SharedStore.write(Self.snapshot(accounts: 0), to: url)

        guard case .snapshot(let restored) = SharedStore.reading(from: url) else {
            Issue.record("an empty reading was mistaken for one that could not be read")
            return
        }
        #expect(restored.accounts.isEmpty)
    }

    @Test func aFileNobodyHasWrittenIsNotUnreadable() {
        #expect(SharedStore.reading(from: Self.temporaryURL()) == .nothingWritten)
    }

    /// The real failure, arranged the only way a test can arrange it. macOS
    /// refuses the container with a permission error, and a file this process
    /// may not open produces the same kind.
    @Test func aFileThatCannotBeOpenedIsUnreadable() throws {
        try #require(getuid() != 0, "root may open anything, so this proves nothing")

        let url = Self.temporaryURL()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: url)
        }

        SharedStore.write(Self.snapshot(accounts: 3), to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: url.path)

        #expect(SharedStore.reading(from: url) == .unreadable, """
            a snapshot this process is not allowed to open read as one nobody \
            has written — which is what puts "No accounts found" in front of \
            somebody who has four
            """)
    }

    @Test func aFileThatIsNotASnapshotIsUnreadable() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try Data("half a fi".utf8).write(to: url)
        #expect(SharedStore.reading(from: url) == .unreadable)
    }

    /// `read` is what the iPhone widget and the app's own copy still call, and
    /// it must go on answering `nil` for anything that is not a snapshot.
    @Test func theOlderAnswerIsUnchanged() throws {
        let url = Self.temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(SharedStore.read(from: url) == nil)
        SharedStore.write(Self.snapshot(accounts: 1), to: url)
        #expect(SharedStore.read(from: url)?.accounts.count == 1)
    }
}

/// The widget has to act on the distinction, not merely be handed it.
///
/// Read from the source, like the widget's other rules: a widget on a desktop
/// and a container macOS refuses is not a situation a test can arrange.
@Suite struct TheWidgetDrawsTheDifference {

    @Test func theEmptyStateIsNotUsedForAReadingThatFailed() throws {
        let view = try String(contentsOf: Self.widgetView, encoding: .utf8)

        #expect(view.contains("case .unreadable"), """
            the widget draws one empty state for every outcome again — a \
            container it may not open says "No accounts found", about accounts \
            that are still there
            """)
        #expect(view.contains("No accounts found"), "the honest empty state is gone")
    }

    /// The sentence that names the real cause must not be spent on the case
    /// where the app truthfully found nothing.
    @Test func eachStateKeepsItsOwnWords() throws {
        let view = try String(contentsOf: Self.widgetView, encoding: .utf8)
        let unreadable = try #require(Self.body(of: "private var unreadable", in: view),
                                      "the view for an unreadable container is gone")
        let empty = try #require(Self.body(of: "private var empty", in: view),
                                 "the empty state is gone")

        #expect(unreadable != empty, "the two states are drawn by one view again")
        #expect(!unreadable.contains("No accounts found"), """
            the state for a container that could not be read says "No accounts \
            found" — which is the claim it exists to stop being made
            """)
        #expect(empty.contains("No accounts found"), "the honest empty state lost its words")
    }

    /// One declaration's body, by counting braces from its first one.
    ///
    /// The check this replaces compared `view[unreadable...]` against
    /// `view[empty...]` — two suffixes of one file taken at different offsets,
    /// which differ by their length alone. It passed however the two states
    /// were drawn, including when one was a copy of the other, which is the
    /// regression it names.
    private static func body(of declaration: String, in source: String) -> Substring? {
        guard let start = source.range(of: declaration) else { return nil }
        var depth = 0
        var opened: String.Index?
        var index = start.upperBound
        while index < source.endIndex {
            switch source[index] {
            case "{":
                if depth == 0 { opened = index }
                depth += 1
            case "}":
                depth -= 1
                if depth == 0, let opened { return source[opened...index] }
            default:
                break
            }
            index = source.index(after: index)
        }
        return nil
    }

    private static var widgetView: URL {
        root.appendingPathComponent("Widget/LimitsWidgetView.swift")
    }

    private static var root: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
}
