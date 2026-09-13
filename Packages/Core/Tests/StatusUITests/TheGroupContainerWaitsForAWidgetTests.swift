import Testing
import Foundation

/// Nothing reaches into the app group container until a widget is there to read
/// what it finds.
///
/// The container is shared with the widget, and macOS guards a shared container
/// as "data from other apps" whenever the signature cannot prove the app belongs
/// to the team the group is filed under — which an ad-hoc signature never can.
/// The prompt is worded as though the app were reading somebody else's files; it
/// is reading its own, and no wording of ours can correct the sentence macOS
/// shows.
///
/// So the only cure is not to go there. The app's own reasons for keeping a
/// reading — the tracker's baseline, the history behind the statistics screen —
/// are served from its own directory, which needs no permission. The shared copy
/// exists for one reader, and is written when that reader exists.
///
/// Held by reading the source because the alternative is a widget on a screen
/// and a permission dialog to answer, which no test can arrange.
@Suite struct TheGroupContainerWaitsForAWidget {

    @Test func theHistoryLivesOutsideTheGroupContainer() throws {
        let store = try String(contentsOf: Self.sharedSnapshot, encoding: .utf8)

        guard let history = Self.property("historyURL", in: store) else {
            throw ScanIsLookingInTheWrongPlace(what: "historyURL", found: 0, least: 1)
        }
        #expect(history.contains("localURL"), """
            the history is built from the group container again — opening it is \
            what asks for permission, and the statistics screen is not the widget
            """)
    }

    @Test func theBaselineIsReadFromTheAppsOwnCopy() throws {
        let model = try String(contentsOf: Self.appModel, encoding: .utf8)
        guard let seeding = Self.function("seedTrackerFromDisk", in: model) else {
            throw ScanIsLookingInTheWrongPlace(what: "seedTrackerFromDisk", found: 0, least: 1)
        }
        #expect(seeding.contains("readLocal"),
                "the baseline is read from the shared container at launch again")
    }

    /// The write to the shared copy sits behind the question, and the app's own
    /// copy does not — one is for a reader who may not exist, the other is for
    /// the next launch, which always does.
    @Test func theSharedCopyIsWrittenOnlyWhenAWidgetExists() throws {
        let model = try String(contentsOf: Self.appModel, encoding: .utf8)
        guard let publish = Self.function("publishToWidget", in: model) else {
            throw ScanIsLookingInTheWrongPlace(what: "publishToWidget", found: 0, least: 1)
        }

        #expect(publish.contains("SharedStore.writeLocal("), """
            the app stopped keeping its own copy — the tracker's baseline and the \
            statistics history both come from it
            """)

        guard let asks = publish.range(of: "aWidgetIsOnScreen"),
              let shares = publish.range(of: "SharedStore.write(") else {
            Issue.record("""
                the shared write is no longer guarded by a check for a widget — \
                every launch would ask to access data from other apps again
                """)
            return
        }
        #expect(asks.lowerBound < shares.lowerBound, """
            the shared container is written before anything asks whether a widget \
            is there to read it
            """)
    }

    // MARK: - reading

    private static func property(_ name: String, in source: String) -> String? {
        block(after: "var \(name): URL? {", in: source)
    }

    private static func function(_ name: String, in source: String) -> String? {
        block(after: "func \(name)(", in: source)
    }

    /// From the declaration to the closing brace at the declaration's own
    /// indentation — taken by shape, so an edit that moves it does not blind the
    /// scan.
    private static func block(after opening: String, in source: String) -> String? {
        guard let start = source.range(of: opening) else { return nil }
        let rest = source[start.upperBound...]
        guard let end = rest.range(of: "\n    }") else { return nil }
        return String(rest[..<end.lowerBound])
    }

    private static var sharedSnapshot: URL {
        root.appendingPathComponent("Packages/Core/Sources/StatusUI/SharedSnapshot.swift")
    }
    private static var appModel: URL { root.appendingPathComponent("App/AppModel.swift") }

    private static var root: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
}
