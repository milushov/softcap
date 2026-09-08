import Testing
import Foundation
@testable import Preferences

@Test func describesModifiersInAppleOrder() {
    // The order macOS uses for the signs: ⌃ ⌥ ⇧ ⌘
    let combo = HotKeyCombo(keyCode: 37, modifiers: HotKeyCombo.command | HotKeyCombo.option)
    #expect(combo.displayString == "⌥⌘L")
}

@Test func describesSingleModifier() {
    #expect(HotKeyCombo(keyCode: 37, modifiers: HotKeyCombo.command).displayString == "⌘L")
}

@Test func describesAllFourModifiers() {
    let all = HotKeyCombo.control | HotKeyCombo.option | HotKeyCombo.shift | HotKeyCombo.command
    #expect(HotKeyCombo(keyCode: 37, modifiers: all).displayString == "⌃⌥⇧⌘L")
}

@Test func unknownKeyCodeFallsBackToNumber() {
    #expect(HotKeyCombo(keyCode: 999, modifiers: HotKeyCombo.command).displayString == "⌘#999")
}

@Test func hotKeySurvivesEncodingRoundTrip() throws {
    let combo = HotKeyCombo(keyCode: 15, modifiers: HotKeyCombo.command)
    let data = try JSONEncoder().encode(combo)
    #expect(try JSONDecoder().decode(HotKeyCombo.self, from: data) == combo)
}
