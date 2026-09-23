import Testing
import Foundation

/// Every clickable thing in this app is a borderless button — no frame, no
/// fill, often one word inside a line of text — and until `ClickableButton`
/// none of them said so. The pointer passed over the period label, the three
/// symbols in the popover's footer and the sidebar's entries without changing,
/// and nothing lit up underneath it.
///
/// Two signals, both the system's: the fill macOS draws behind the menu item
/// under the pointer, and the hand it shows over anything pressable. This suite
/// holds what the first attempt got wrong as much as what the affordance does —
/// it was a modifier applied *after* `.buttonStyle(.plain)`, which padded a
/// parent of the button, so the fill and the hand answered for a chip that the
/// press did not. Half of what lit up on the footer's symbols did nothing.
@Suite struct EveryClickableThingSaysSo {

    // MARK: the style

    @Test func theFillAndTheHandAreBothThere() throws {
        let style = try Self.style()
        #expect(style.contains(".fill(.quaternary)"), "the hover fill is gone")
        #expect(style.contains("pointerStyle("), "the hand is gone")
    }

    /// The whole point of it being a style: the padding goes inside
    /// `configuration.label`, so the rectangle that lights up is the button.
    @Test func theChipIsTheButtonAndNotAParentOfIt() throws {
        let style = try Self.style()
        #expect(style.contains(": ButtonStyle"), """
            the affordance is not a button style any more — applied from \
            outside, it pads a parent of the button and lights up an area the \
            press does not reach
            """)
        guard let label = style.range(of: "configuration.label"),
              let padding = style.range(of: ".padding(.horizontal, inset.width)") else {
            Issue.record("the style no longer pads its own label")
            return
        }
        #expect(label.lowerBound < padding.lowerBound,
                "the padding is no longer applied to the button's own label")
        #expect(!style.contains("-inset.width"), """
            the padding is taken back with negative padding again — the chip is \
            drawn and hovered outside the frame the button reports, which is \
            the arrangement whose press did not follow its own highlight
            """)
    }

    /// Rectangular hit shape under a rounded fill. The sidebar's rows claim
    /// their corners with a `.contentShape(Rectangle())` of their own, and an
    /// ancestor's shape gates everything under it.
    @Test func theCornersAreDrawnAwayRatherThanTakenAway() throws {
        #expect(try Self.style().contains(".contentShape(Rectangle())"), """
            the hit shape follows the rounded fill, so a press three points \
            into the corner of a sidebar row now falls through it
            """)
    }

    /// `NSCursor` is the other way to do this and is banned here twice over:
    /// `CoreStaysPortable` allows no AppKit in this package at all, and a
    /// pushed cursor outlives the view it was pushed for when the view goes
    /// away under the pointer — which is what a closing popover does to every
    /// row in it.
    @Test func theHandIsSwiftUIsAndIsAskedForByVersion() throws {
        let style = try Self.style()
        #expect(style.contains("#if os(macOS)"), """
            the pointer style is no longer behind an os check — it is macOS \
            API, and this package is built for the phone as well
            """)
        #expect(style.contains("if #available(macOS 15.0, *)"), """
            the pointer style is no longer behind an availability check — it \
            arrived in macOS 15 and the app supports 14, where this would not \
            compile
            """)
        // The call, not the word: the style's own comment says what it does not
        // use and why, and a check written against the name failed on the
        // explanation. `TheMutationToolSaysWhatItDoes` records the same lesson.
        #expect(!style.contains("NSCursor."), """
            the hand comes from NSCursor again: AppKit is banned in this \
            package, and a pushed cursor stays on screen when the view under \
            the pointer is taken away without a mouse-exit
            """)
    }

    /// The same explicit forgetting the peek needs, for the same reason.
    @Test func theFillIsForgottenWhenTheViewGoesAway() throws {
        #expect(try Self.style().contains("onDisappear { hovering = false }"), """
            the hover flag is no longer cleared when the view disappears — the \
            popover is cached, so the fill would be waiting at the next \
            opening with the pointer nowhere near it
            """)
    }

    /// A button that is refusing to be pressed promises neither, and does not
    /// have to be told: inside a style the environment already knows.
    @Test func aRefusingButtonPromisesNeitherFillNorHand() throws {
        let style = try Self.style()
        #expect(style.contains("@Environment(\\.isEnabled)"), """
            whether the button is enabled is a parameter again — every call \
            site then has to remember to pass it, and the × inside the disabled \
            Thresholds section is the one that did not
            """)
        #expect(style.contains("if hovering && isEnabled"), "a disabled control still lights up")
        #expect(style.contains(".pointingHand(isEnabled)")
                && style.contains("pointerStyle(enabled ? .link : nil)"),
                "a disabled control still shows the hand")
    }

    /// `.plain` dims its label while it is held. Replacing it with a style that
    /// does not would have taken that away from every button in the app.
    @Test func aHeldButtonStillSaysItIsHeld() throws {
        #expect(try Self.style().contains("configuration.isPressed"),
                "nothing happens while a button is held any more")
    }

    // MARK: everything that is clickable

    /// The invariant, and it is now an absence rather than a count: there is no
    /// `.plain` left anywhere, so a borderless button cannot be given one
    /// without this failing. The previous version counted affordances against
    /// buttons per file, which two changes in one file could balance out.
    @Test func noButtonIsLeftBareInAnySource() throws {
        var bare: [String] = []
        for path in try Self.everySwiftSource() {
            // The style's own file says what it replaced and why, in prose. A
            // check written against the words rather than the calls trips over
            // the explanation — `TheMutationToolSaysWhatItDoes` again.
            guard !path.hasSuffix("ClickableButton.swift") else { continue }
            let text = try Self.source(path)
            for style in ["buttonStyle(.plain)", "PlainButtonStyle()", "buttonStyle(.borderless)"]
            where text.contains(style) {
                bare.append("\(path): \(style)")
            }
        }
        #expect(bare.isEmpty, """
            borderless buttons with nothing under the pointer: \(bare.sorted()) \
            — every one of them should be `.buttonStyle(.clickable)`, which is \
            the same look with the fill and the hand
            """)
    }

    /// And that something wears the affordance at all — an app with no buttons
    /// left would pass the test above without a word.
    @Test func theClickableThingsAreStillThere() throws {
        var worn = 0
        for path in try Self.everySwiftSource() {
            worn += try Self.source(path).components(separatedBy: ".clickable").count - 1
        }
        #expect(worn >= 8, """
            only \(worn) uses of the affordance were found, where eleven \
            buttons wear it — either the scan is looking in the wrong place or \
            most of the app's controls have gone
            """)
    }

    // MARK: -

    /// Every Swift file in the app and in the package, the phone and the widget
    /// included: they build from the same `StatusUI`, and a bare button added
    /// to one of them is a bare button.
    private static func everySwiftSource() throws -> [String] {
        var found: [String] = []
        for root in ["App", "Packages/Core/Sources", "Widget", "iOS", "iOSWidget"] {
            let directory = repositoryRoot().appendingPathComponent(root)
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }
            let walker = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: nil)
            while let url = walker?.nextObject() as? URL {
                guard url.pathExtension == "swift" else { continue }
                found.append(String(url.path.dropFirst(repositoryRoot().path.count + 1)))
            }
        }
        // A floor that proves the walk found the sources, well under the
        // hundred-odd files there are: this is not a count of today's tree.
        guard found.count >= 40 else {
            throw ScanIsLookingInTheWrongPlace(
                what: "app and package sources", found: found.count, least: 40)
        }
        return found.sorted()
    }

    private static func style() throws -> String {
        let text = try source("Packages/Core/Sources/StatusUI/ClickableButton.swift")
        guard text.count >= 2_000 else {
            throw ScanIsLookingInTheWrongPlace(
                what: "ClickableButton", found: text.count, least: 2_000)
        }
        return text
    }

    private static func source(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent(path), encoding: .utf8)
    }

    private static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // …/StatusUITests
            .deletingLastPathComponent()      // …/Tests
            .deletingLastPathComponent()      // …/Core
            .deletingLastPathComponent()      // …/Packages
            .deletingLastPathComponent()      // repository root
    }
}
