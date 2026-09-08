import Foundation
import AppKit
import SwiftUI
import Carbon.HIToolbox
import Preferences

/// Global keyboard shortcuts.
///
/// Carbon's `RegisterEventHotKey` is the only way to get a shortcut that works
/// outside the active app without asking for Accessibility permissions. It has
/// no modern replacement.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var handler: EventHandlerRef?

    private init() { installHandler() }

    func register(_ combo: HotKeyCombo?, id: UInt32, action: @escaping () -> Void) {
        unregister(id: id)
        guard let combo else { return }

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x53544348), id: id)  // 'STCH'
        let status = RegisterEventHotKey(
            combo.keyCode, combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return }

        refs[id] = ref
        actions[id] = action
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        actions[id] = nil
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
    }

    private func installHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var id = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &id
                )
                let pressed = id.id
                Task { @MainActor in HotKeyCenter.shared.fire(pressed) }
                return noErr
            },
            1, &spec, nil, &handler
        )
    }
}

enum HotKeyID {
    static let openWindow: UInt32 = 1
    static let refresh: UInt32 = 2
}

/// Captures one key press and reports it as a combination.
/// Through an `NSView`, because SwiftUI does not expose key codes and modifiers
/// in the form Carbon expects.
struct HotKeyRecorder: NSViewRepresentable {
    let isActive: Bool
    let onCapture: (HotKeyCombo) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.onCapture = onCapture
        if isActive { view.window?.makeFirstResponder(view) }
    }

    final class RecorderView: NSView {
        var onCapture: ((HotKeyCombo) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            var modifiers: UInt32 = 0
            if event.modifierFlags.contains(.control) { modifiers |= HotKeyCombo.control }
            if event.modifierFlags.contains(.option) { modifiers |= HotKeyCombo.option }
            if event.modifierFlags.contains(.shift) { modifiers |= HotKeyCombo.shift }
            if event.modifierFlags.contains(.command) { modifiers |= HotKeyCombo.command }

            // A shortcut without modifiers would swallow ordinary typing.
            guard modifiers != 0 else { NSSound.beep(); return }
            onCapture?(HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers))
        }
    }
}
