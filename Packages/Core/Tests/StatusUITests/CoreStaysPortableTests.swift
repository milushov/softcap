import Testing
import Foundation

/// `Packages/Core` is written to run on both platforms — the landing says so, and
/// the iPhone app is built out of the same modules. The iOS build already proves
/// it, but only when somebody runs it; this proves it in three seconds on every
/// `make test`, and names the file rather than failing somewhere in a compile.
@Suite struct CoreStaysPortable {

    /// Frameworks that exist on macOS and not on iOS. Importing one outside an
    /// `#if os(macOS)` breaks the phone build.
    private static let macOnly = [
        "AppKit", "CoreServices", "Carbon", "ServiceManagement", "IOKit", "ScriptingBridge",
    ]

    /// The page claims the core has no AppKit in it. That one is absolute: there
    /// is no reason for a model or a provider to reach for the Mac's UI toolkit
    /// even behind a guard.
    @Test func noAppKitAnywhereInTheCore() throws {
        let offenders = try Self.sources().filter { url in
            let text = try? String(contentsOf: url, encoding: .utf8)
            return text?.contains("import AppKit") ?? false
        }
        #expect(offenders.isEmpty,
                "AppKit in the core: \(offenders.map(\.lastPathComponent).sorted())")
    }

    @Test func everyMacOnlyImportSitsBehindAGuard() throws {
        var offenders: [String] = []
        for url in try Self.sources() {
            let text = try String(contentsOf: url, encoding: .utf8)
            var depth = 0
            for line in text.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#if os(macOS)") { depth += 1 }
                else if trimmed.hasPrefix("#endif") { depth = max(0, depth - 1) }
                else if trimmed.hasPrefix("import "),
                        let framework = trimmed.split(separator: " ").last.map(String.init),
                        Self.macOnly.contains(framework), depth == 0 {
                    offenders.append("\(url.lastPathComponent): \(framework)")
                }
            }
        }
        #expect(offenders.isEmpty, """
            imported on both platforms but present on one: \(offenders.sorted()) \
            — wrap it in #if os(macOS), as KeychainAccess does for Security
            """)
    }

    /// Types the Mac has and the phone does not, which no import check can see.
    ///
    /// `Security` exists on both platforms; `SecStaticCode` is in the macOS SDK
    /// alone. `Process` is Foundation's and is absent from iOS entirely. A
    /// module using either compiles here and fails there, and `Updates` did —
    /// while this suite, which exists to make exactly that a named
    /// three-second failure, passed by only ever reading import lines.
    private static let macOnlyAPI = [
        "Process(", "SecStaticCode", "SecCodeCopySigningInformation", "NSWorkspace",
    ]

    @Test func everyMacOnlyApiSitsBehindAguardToo() throws {
        var offenders: [String] = []
        var examined = 0
        for url in try Self.sources() {
            let text = try String(contentsOf: url, encoding: .utf8)
            var depth = 0
            for line in text.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#if os(macOS)") { depth += 1; continue }
                if trimmed.hasPrefix("#endif") { depth = max(0, depth - 1); continue }
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") { continue }
                for name in Self.macOnlyAPI where trimmed.contains(name) {
                    examined += 1
                    if depth == 0 { offenders.append("\(url.lastPathComponent): \(name)") }
                }
            }
        }

        // Vacuous otherwise: nothing found means nothing checked.
        guard examined >= 3 else {
            throw ScanIsLookingInTheWrongPlace(
                what: "Mac-only API use", found: examined, least: 3)
        }

        #expect(offenders.isEmpty, """
            used on both platforms and present on one: \(offenders.sorted()) \
            — wrap it in #if os(macOS), as UpdateInstaller does for Process and SecStaticCode
            """)
    }

    private static func sources() throws -> [URL] {
        let found = try walksources()
        guard found.count >= 10 else {
            throw ScanIsLookingInTheWrongPlace(what: "Core sources", found: found.count, least: 10)
        }
        return found
    }

    private static func walksources() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // …/Tests/StatusUITests
            .deletingLastPathComponent()      // …/Tests
            .deletingLastPathComponent()      // …/Core
            .appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}

