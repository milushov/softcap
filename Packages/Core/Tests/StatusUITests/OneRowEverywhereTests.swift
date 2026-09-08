import Testing
import Foundation

/// The Mac window, both widgets and the iPhone screen draw an account with the
/// same view. `AccountRow`'s own comment says why: "a copy in two places would
/// drift apart on the first edit." The landing repeats the claim, so it is worth
/// a check rather than a habit.
///
/// Four surfaces is exactly the number where copying starts to look reasonable —
/// a widget is cramped, a phone is not a Mac — and each copy would be correct on
/// the day it was made.
@Suite struct OneRowDrawnEverywhere {

    /// Where an account is drawn, and the file that draws it.
    private static let surfaces = [
        ("the limits window", "App/PopoverView.swift"),
        ("the macOS widget",  "Widget/LimitsWidgetView.swift"),
        ("the iPhone screen", "iOS/LimitsScreen.swift"),
        ("the iPhone widget", "iOSWidget/PhoneWidgetView.swift"),
    ]

    @Test func everySurfaceDrawsTheSharedRow() throws {
        var missing: [String] = []
        for (what, path) in Self.surfaces {
            let url = Self.repositoryRoot.appendingPathComponent(path)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                missing.append("\(what): \(path) is not there any more")
                continue
            }
            if !text.contains("AccountRow(") { missing.append("\(what) (\(path))") }
        }
        #expect(missing.isEmpty, "no longer drawing the shared row: \(missing.sorted())")
    }

    /// A second view of the same name would satisfy the check above while
    /// defeating the point of it.
    @Test func theRowIsDefinedOnlyOnce() throws {
        let views = try Self.swiftFiles().filter { url in
            let text = try? String(contentsOf: url, encoding: .utf8)
            return text?.contains("struct AccountRow: View") ?? false
        }
        #expect(views.count == 1,
                "AccountRow is a view in \(views.map(\.lastPathComponent).sorted())")
        #expect(views.first?.lastPathComponent == "AccountRow.swift",
                "the shared row moved to \(views.first?.lastPathComponent ?? "nowhere")")
    }

    // MARK: - walking

    /// Production sources only. `Tests` is skipped because this very file
    /// contains the string it searches for, and found itself on the first run —
    /// a check that fails because of its own text is worse than no check.
    private static func swiftFiles() throws -> [URL] {
        let skipped = [".build", ".git", ".claude", "build", "build-ios", "DerivedData", "Tests"]
        guard let walker = FileManager.default.enumerator(
            at: repositoryRoot, includingPropertiesForKeys: nil
        ) else { return [] }
        var found: [URL] = []
        for case let url as URL in walker {
            if skipped.contains(url.lastPathComponent) { walker.skipDescendants(); continue }
            if url.pathExtension == "swift" { found.append(url) }
        }
        return found
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
