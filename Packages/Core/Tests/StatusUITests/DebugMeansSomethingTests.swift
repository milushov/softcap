import Testing
import Foundation

/// `#if DEBUG` compiled to nothing in this project: both configurations share one
/// xcconfig and nothing defined the flag, so a debug build dropped everything
/// guarded by it and said nothing. Nothing was relying on it yet, which is the
/// only reason it cost nothing.
@Suite struct DebugMeansSomething {

    @Test func theDebugConfigurationDefinesDebug() throws {
        let project = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent("project.yml"),
            encoding: .utf8)
        guard let configs = project.range(of: "configs:") else {
            Issue.record("project.yml declares no per-configuration settings")
            return
        }
        let after = String(project[configs.upperBound...].prefix(300))
        #expect(after.contains("Debug:"), "there is no Debug configuration to define it in")
        #expect(after.contains("SWIFT_ACTIVE_COMPILATION_CONDITIONS: DEBUG"), """
            the Debug configuration does not define DEBUG, so every `#if DEBUG` in \
            this project compiles to nothing and says nothing about it
            """)
    }

    /// And not in Release: a shipped build must not carry whatever the debug
    /// branches hold.
    @Test func theReleaseConfigurationDoesNot() throws {
        let project = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent("project.yml"),
            encoding: .utf8)
        guard let release = project.range(of: "\n    Release:") else { return }
        let block = String(project[release.upperBound...].prefix(200))
        #expect(!block.contains("SWIFT_ACTIVE_COMPILATION_CONDITIONS: DEBUG"),
                "the Release configuration defines DEBUG")
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
