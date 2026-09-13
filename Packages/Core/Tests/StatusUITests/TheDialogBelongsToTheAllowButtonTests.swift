import Testing
import Foundation

/// The keychain's access dialog belongs to the "Allow access…" button and to
/// nothing else in the app.
///
/// `PollOrigin` carries the decision — only `.allowingAccess` may raise the
/// dialog — but the decision only holds if the app passes the right origin
/// from the right places. That wiring is what broke: Refresh used to pass the
/// origin that could ask, and on a machine where every account held a grant
/// of the app's own, each press of Refresh demanded the login keychain
/// password for an item nothing needed. A scanner can see the wiring.
private var repositoryRootForDialog: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func appSources() throws -> [(path: String, lines: [String])] {
    var found: [(String, [String])] = []
    let root = repositoryRootForDialog.appendingPathComponent("App")
    guard let walker = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: nil
    ) else { return [] }
    for case let url as URL in walker where url.pathExtension == "swift" {
        let text = try String(contentsOf: url, encoding: .utf8)
        // Comments removed: a rule about code must not fire on the prose
        // that describes the mistake it forbids.
        let lines = text.components(separatedBy: "\n").map { line in
            guard let comment = line.range(of: "//") else { return line }
            return String(line[line.startIndex..<comment.lowerBound])
        }
        found.append(("App/" + url.lastPathComponent, lines))
    }
    return found
}

@Suite struct TheDialogBelongsToTheAllowButton {

    /// Every place that polls with the dialog allowed is an Allow access…
    /// button — the origin that may ask never rides along on anything else.
    @Test func everyGrantSitsOnAnAllowButton() throws {
        var grants = 0
        var strays: [String] = []

        for (path, lines) in try appSources() {
            for (index, line) in lines.enumerated() where line.contains(".allowingAccess") {
                grants += 1
                let start = lines.index(index, offsetBy: -2, limitedBy: 0) ?? 0
                let button = lines[start...index].contains { $0.contains("Allow access") }
                if !button {
                    strays.append("\(path):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        #expect(grants >= 2, """
            only \(grants) grant call sites found where the popover's empty \
            state and the Accounts screen make two — the scan is looking in \
            the wrong place
            """)
        #expect(strays.isEmpty, """
            the origin that may raise the keychain dialog is passed away from \
            any Allow access… button: \(strays.sorted()) — a person there did \
            not ask for a password prompt
            """)
    }

    /// And the other direction: every Allow access… button actually grants.
    /// One quietly downgraded to a plain refresh would leave the setup path
    /// unable to raise the dialog it exists for.
    @Test func everyAllowButtonGrants() throws {
        var buttons = 0
        var broken: [String] = []

        for (path, lines) in try appSources() {
            for (index, line) in lines.enumerated() where line.contains("Allow access") {
                buttons += 1
                let end = lines.index(index, offsetBy: 2, limitedBy: lines.count - 1)
                    ?? lines.count - 1
                let grants = lines[index...end].contains { $0.contains(".allowingAccess") }
                if !grants {
                    broken.append("\(path):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        #expect(buttons >= 2, """
            only \(buttons) Allow access… buttons found where the popover's \
            empty state and the Accounts screen make two — the scan is \
            looking in the wrong place
            """)
        #expect(broken.isEmpty, """
            an Allow access… button that cannot raise the dialog it promises: \
            \(broken.sorted()) — pass `.allowingAccess`
            """)
    }

    /// The store's switch is thrown by the origin table and by nothing else.
    /// Raising it by hand next to one call is exactly how Refresh came to
    /// demand a password.
    @Test func nobodyRaisesTheSwitchByHand() throws {
        var raised: [String] = []

        for (path, lines) in try appSources() {
            for (index, line) in lines.enumerated() where line.contains("setPromptAllowed(true") {
                raised.append("\(path):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }

        #expect(raised.isEmpty, """
            the prompt switch raised by hand: \(raised.sorted()) — consent \
            travels as `PollOrigin.allowingAccess`, nowhere else
            """)
    }
}
