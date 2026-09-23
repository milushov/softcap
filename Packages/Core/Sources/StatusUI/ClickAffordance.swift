import SwiftUI

/// What a control looks like under the pointer: a fill behind it, and the hand.
///
/// Every clickable thing in this app is a plain button — no border, no fill,
/// often a single word in the middle of a line of text. That is the look this
/// app is for, and it left the pointer with nothing to find: the only way to
/// learn that the period label could be clicked was to click it. The two
/// signals here are the system's own — the soft fill macOS draws behind the
/// menu item under the pointer, and the hand it shows over anything that can
/// be pressed.
///
/// The fill is drawn outside the layout. The control is padded, given its
/// shape, and unpadded again, so a word that gains a highlight does not push
/// the words beside it sideways — which matters directly in
/// `MinimalAccountRow`, where those words are columns that are supposed to
/// line up down the window. The hover and the pointer are read from the padded
/// chip rather than from the glyphs, so the fill appears a little before the
/// pointer is on the letters themselves, which is how a control of this size
/// should behave.
///
/// The hand is SwiftUI's own `pointerStyle`, and that is macOS 15. `NSCursor`
/// would have reached macOS 14 and is not here for two reasons.
/// `CoreStaysPortable` bans AppKit from this package absolutely — the phone
/// builds out of these same modules. And pushing a cursor on hover leaves the
/// hand on screen when the view goes away underneath it without a mouse-exit,
/// which is what a closing popover does to every row in it, and what the
/// `onDisappear` below already exists to undo for the fill. On macOS 14 the
/// fill is the whole affordance.
public struct ClickAffordance: ViewModifier {
    private let enabled: Bool
    private let inset: CGSize
    private let radius: CGFloat

    @State private var hovering = false

    public init(enabled: Bool, inset: CGSize, radius: CGFloat) {
        self.enabled = enabled
        self.inset = inset
        self.radius = radius
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    public func body(content: Content) -> some View {
        content
            .padding(.horizontal, inset.width)
            .padding(.vertical, inset.height)
            .contentShape(shape)
            .background { if hovering && enabled { shape.fill(.quaternary) } }
            // Both of these before the padding is taken back, and that order is
            // the whole trick: they answer for the chip, which is the thing
            // drawn and the thing the pointer meets, while the negative padding
            // below decides only how much room the row gives it — none.
            .onHover { hovering = $0 }
            // The popover is cached and its rows are taken off screen under
            // the pointer, which produces no mouse-exit: without this the fill
            // would be waiting at the next opening, under a pointer that is
            // somewhere else entirely. The peek in `MinimalAccountRow` is
            // forgotten in the same place for the same reason.
            .onDisappear { hovering = false }
            .pointingHand(enabled)
            .padding(.horizontal, -inset.width)
            .padding(.vertical, -inset.height)
    }
}

public extension View {

    /// See `ClickAffordance`. Every plain button in the app wears this.
    ///
    /// `enabled` is the button's own, not the pointer's: a control that is
    /// refusing to be pressed should not light up or promise a hand, and
    /// `.disabled` does neither of those things to a plain button — the same
    /// gap `SignInPrompt` works around for its colour.
    func clickAffordance(
        enabled: Bool = true,
        inset: CGSize = CGSize(width: 5, height: 2),
        radius: CGFloat = 4
    ) -> some View {
        modifier(ClickAffordance(enabled: enabled, inset: inset, radius: radius))
    }
}

extension View {

    /// The hand, where the system can draw it — see `ClickAffordance` for why
    /// it is this and not `NSCursor`, and why macOS 14 does without.
    @ViewBuilder
    func pointingHand(_ enabled: Bool) -> some View {
        #if os(macOS)
        if #available(macOS 15.0, *) {
            pointerStyle(enabled ? .link : nil)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
