import Testing
import Foundation

/// Every clickable thing in this app is a plain button — no border, no fill,
/// often one word inside a line of text — and until `ClickAffordance` none of
/// them said so. The pointer passed over the period label, the three symbols
/// in the popover's footer and the sidebar's entries without changing, and
/// nothing lit up underneath it.
///
/// Two signals, both the system's: the fill macOS draws behind the menu item
/// under the pointer, and the hand it shows over anything pressable. This
/// suite holds three things about them — that the modifier still does both,
/// that doing them costs the layout nothing, and that every plain button in
/// the app wears it.
@Suite struct EveryClickableThingSaysSo {

    // MARK: the modifier

    @Test func theFillAndTheHandAreBothThere() throws {
        let affordance = try Self.source("Packages/Core/Sources/StatusUI/ClickAffordance.swift")
        #expect(affordance.contains("shape.fill(.quaternary)"), "the hover fill is gone")
        #expect(affordance.contains("pointerStyle("), "the hand is gone")
    }

    /// `NSCursor` is the other way to do this and is banned here twice over:
    /// `CoreStaysPortable` allows no AppKit in this package at all, and a
    /// pushed cursor outlives the view it was pushed for when the view goes
    /// away under the pointer — which is what a closing popover does to every
    /// row in it.
    @Test func theHandIsSwiftUIsAndIsAskedForByVersion() throws {
        let affordance = try Self.source("Packages/Core/Sources/StatusUI/ClickAffordance.swift")
        #expect(affordance.contains("#if os(macOS)"), """
            the pointer style is no longer behind an os check — it is macOS \
            API, and this package is built for the phone as well
            """)
        #expect(affordance.contains("if #available(macOS 15.0, *)"), """
            the pointer style is no longer behind an availability check — it \
            arrived in macOS 15 and the app supports 14, where this would not \
            compile
            """)
        // The call, not the word: the modifier's own comment says what it does
        // not use and why, and a check written against the name failed on the
        // explanation. `TheMutationToolSaysWhatItDoes` records the same lesson.
        #expect(!affordance.contains("NSCursor."), """
            the hand comes from NSCursor again: AppKit is banned in this \
            package, and a pushed cursor stays on screen when the view under \
            the pointer is taken away without a mouse-exit
            """)
    }

    /// The order is the whole trick. The control is padded so the fill and the
    /// pointer answer for a chip bigger than the glyphs, and the padding is
    /// taken back afterwards so the row gives that chip no room — a word that
    /// lit up and pushed its neighbours sideways would undo `TheRowsLineUp`
    /// every time the pointer crossed it.
    @Test func theChipCostsTheLayoutNothingAndStillCatchesThePointer() throws {
        let affordance = try Self.source("Packages/Core/Sources/StatusUI/ClickAffordance.swift")
        guard let hover = affordance.range(of: ".onHover"),
              let unpad = affordance.range(of: ".padding(.horizontal, -inset.width)") else {
            Issue.record("the modifier no longer reads hover, or no longer takes its padding back")
            return
        }
        #expect(hover.lowerBound < unpad.lowerBound, """
            the hover is read after the padding is taken back, so it answers \
            for the glyphs and not for the chip that is drawn around them
            """)
    }

    /// The same explicit forgetting the peek needs, for the same reason.
    @Test func theFillIsForgottenWhenTheViewGoesAway() throws {
        #expect(try Self.source("Packages/Core/Sources/StatusUI/ClickAffordance.swift")
            .contains("onDisappear { hovering = false }"), """
            the hover flag is no longer cleared when the view disappears — the \
            popover is cached, so the fill would be waiting at the next \
            opening with the pointer nowhere near it
            """)
    }

    /// A button that is refusing to be pressed should promise neither. It has
    /// to be told, because `.disabled` does nothing visible to a plain button
    /// — the same gap `SignInPrompt` works around for its colour.
    @Test func aRefusingButtonPromisesNeitherFillNorHand() throws {
        let affordance = try Self.source("Packages/Core/Sources/StatusUI/ClickAffordance.swift")
        #expect(affordance.contains("if hovering && enabled"), "a disabled control still lights up")
        #expect(affordance.contains("pointerStyle(enabled ? .link : nil)"),
                "a disabled control still shows the hand")
    }

    // MARK: everything that is clickable

    /// The invariant, rather than a list that goes stale: a file with plain
    /// buttons in it has at least as many affordances as it has buttons. A
    /// tenth plain button added next year without one fails here, naming the
    /// file it was added to.
    @Test func everyPlainButtonInTheAppWearsIt() throws {
        for path in try Self.sourcesWithPlainButtons() {
            let text = try Self.source(path)
            let buttons = text.components(separatedBy: "buttonStyle(.plain)").count - 1
            let worn = text.components(separatedBy: ".clickAffordance(").count - 1
            #expect(worn >= buttons, """
                \(path) has \(buttons) plain button(s) and \(worn) affordance(s) \
                — a borderless button with nothing under the pointer is the \
                thing this was written to stop
                """)
        }
    }

    /// The two in the package, named rather than counted: these are the ones
    /// the window in the screenshots is made of.
    @Test func theRowAndTheSignInOfferWearIt() throws {
        #expect(try Self.source("Packages/Core/Sources/StatusUI/MinimalAccountRow.swift")
            .contains(".clickAffordance()"), """
            the period label lost its affordance — it is a word in the middle \
            of a line of text and the only way left to learn it can be \
            clicked is to click it
            """)
        #expect(try Self.source("Packages/Core/Sources/StatusUI/SignInOffer.swift")
            .contains(".clickAffordance(enabled: enabled)"), """
            the sign-in button lost its affordance, or stopped passing its own \
            enabled state to it
            """)
    }

    // MARK: -

    private static func sourcesWithPlainButtons() throws -> [String] {
        var found: [String] = []
        for root in ["App", "Packages/Core/Sources"] {
            let directory = repositoryRoot().appendingPathComponent(root)
            let walker = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: nil)
            while let url = walker?.nextObject() as? URL {
                guard url.pathExtension == "swift" else { continue }
                let text = try String(contentsOf: url, encoding: .utf8)
                guard text.contains("buttonStyle(.plain)") else { continue }
                found.append(String(url.path.dropFirst(repositoryRoot().path.count + 1)))
            }
        }
        guard found.count >= 6 else {
            throw ScanIsLookingInTheWrongPlace(
                what: "plain buttons", found: found.count, least: 6)
        }
        return found.sorted()
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
