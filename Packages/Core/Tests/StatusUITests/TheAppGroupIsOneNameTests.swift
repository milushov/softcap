import Testing
import Foundation

/// Five files name the app group; they have to name the same one.
///
/// The app writes the snapshot into a group container and the widgets read it
/// from there. If an entitlements file and the constant in the code disagree,
/// macOS finds no entitlement ending in the name the code is looking for, falls
/// back to that name, and asks for a container the binary was never granted —
/// `containerURL` returns nil, nothing is written, and the widget shows "No
/// accounts found" for ever. On iOS the constant is used directly, so the
/// mismatch is immediate and just as quiet.
///
/// There is no error to see in either case, on any surface. The only symptom is
/// a widget that never fills in, which reads like a widget nobody has set up.
@Suite struct TheAppGroupIsOneName {

    @Test func everyEntitlementNamesTheGroupTheCodeLooksFor() throws {
        let source = try String(
            contentsOf: Self.root.appendingPathComponent(
                "Packages/Core/Sources/StatusUI/SharedSnapshot.swift"
            ),
            encoding: .utf8
        )
        guard let base = Self.first(#"baseGroup = "([^"]+)""#, in: source) else {
            Issue.record("the code no longer names a base group"); return
        }

        let entitlements = [
            "App/Softcap.entitlements",
            "Widget/SoftcapWidget.entitlements",
            "iOS/SoftcapiOS.entitlements",
            "iOSWidget/SoftcapiOSWidget.entitlements",
        ]
        for name in entitlements {
            let plist = try String(
                contentsOf: Self.root.appendingPathComponent(name), encoding: .utf8
            )
            let groups = Self.all(#"<string>([^<]*group[^<]*)</string>"#, in: plist)
            #expect(!groups.isEmpty, "\(name) declares no application group")
            for group in groups {
                // macOS needs `$(TeamIdentifierPrefix)` in front and iOS must not
                // have it; both end in the name the code goes looking for.
                #expect(group.hasSuffix(base), """
                    \(name) declares \(group), and the code looks for one ending \
                    in \(base) — the app would write where the widget does not read
                    """)
                let wantsPrefix = name.hasPrefix("App/") || name.hasPrefix("Widget/")
                #expect(group.hasPrefix("$(TeamIdentifierPrefix)") == wantsPrefix, """
                    \(name) declares \(group): macOS groups take the team prefix \
                    and iOS groups do not
                    """)
            }
        }
    }

    private static func first(_ pattern: String, in text: String) -> String? {
        all(pattern, in: text).first
    }

    private static func all(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    private static var root: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
}
