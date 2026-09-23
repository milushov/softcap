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
/// **A style rather than a modifier, and that is the whole of the difference.**
/// The first version of this was `.clickAffordance()` applied after
/// `.buttonStyle(.plain)`, which padded and shaped a *parent* of the button:
/// the fill and the hand answered for the padded chip while the press answered
/// for the glyphs alone, so at the popover's three symbols — an 11-point glyph
/// lit over a 23-point chip — about half of what lit up did nothing when
/// pressed. A control that offers to be pressed where it cannot be is worse
/// than one that offers nothing. Here the padding goes inside
/// `configuration.label`, so one rectangle is lit, hovered, pointed at and
/// pressed.
///
/// Three more things follow from being a style. `isEnabled` comes from the
/// environment, so a button inside a disabled section — the whole Thresholds
/// block, when notifications are off — neither lights up nor promises a hand,
/// without every call site having to remember to say so. `isPressed` is
/// available, so the label dims while it is held, which `.plain` did for
/// itself and would otherwise have been lost. And the affordance cannot be
/// forgotten: there is no `.plain` left to apply instead, which is what
/// `EveryClickableThingSaysSo` reads.
///
/// The hit shape is a rectangle while the fill is rounded. The corners are
/// drawn away, not taken away: a press three points into the corner of a
/// sidebar row is a press on the row, and `.contentShape` on an ancestor gates
/// hit-testing for everything under it, so a rounded hit shape here would have
/// bitten those corners out of a row whose own label had deliberately claimed
/// them.
///
/// The hand is SwiftUI's own `pointerStyle`, and that is macOS 15. `NSCursor`
/// would have reached macOS 14 and is not here for two reasons.
/// `CoreStaysPortable` bans AppKit from this package absolutely — the phone
/// builds out of these same modules. And pushing a cursor on hover leaves the
/// hand on screen when the view goes away underneath it without a mouse-exit,
/// which is what a closing popover does to every row in it, and what the
/// `onDisappear` below already exists to undo for the fill. On macOS 14 the
/// fill is the whole affordance.
public struct ClickableButton: ButtonStyle {
    public let inset: CGSize
    public let radius: CGFloat

    public init(inset: CGSize, radius: CGFloat) {
        self.inset = inset
        self.radius = radius
    }

    public func makeBody(configuration: Configuration) -> some View {
        Chip(configuration: configuration, inset: inset, radius: radius)
    }

    /// A view of its own, because a style is not one: `@Environment` and
    /// `@State` read nothing declared on the style itself, and this needs
    /// both — whether the button is taking presses at all, and whether the
    /// pointer is over it.
    private struct Chip: View {
        let configuration: Configuration
        let inset: CGSize
        let radius: CGFloat

        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, inset.width)
                .padding(.vertical, inset.height)
                .contentShape(Rectangle())
                .background {
                    if hovering && isEnabled {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(.quaternary)
                    }
                }
                .opacity(configuration.isPressed ? 0.55 : 1)
                .onHover { hovering = $0 }
                // The popover is cached and its rows are taken off screen under
                // the pointer, which produces no mouse-exit: without this the
                // fill would be waiting at the next opening, under a pointer
                // that is somewhere else entirely. The peek in
                // `MinimalAccountRow` is forgotten in the same place for the
                // same reason.
                .onDisappear { hovering = false }
                .pointingHand(isEnabled)
        }
    }
}

public extension ButtonStyle where Self == ClickableButton {

    /// The affordance at its usual size: a word or a short label.
    ///
    /// Wide and barely tall, and the height is the considered half. The chip
    /// is drawn inside the button now, so whatever room it takes is room the
    /// line around it gives up: at two points the minimal window grew by
    /// eighteen — three rows, the demo note and the footer, each a little
    /// taller — which is a lot to spend on a highlight in a window whose
    /// argument is that it is small. At one the padded word is still shorter
    /// than the account name beside it, so no row grows at all.
    static var clickable: ClickableButton {
        ClickableButton(inset: CGSize(width: 5, height: 1), radius: 4)
    }

    /// The same, sized for what it is wrapping — a bare glyph wants more room
    /// around it than a word does, and a control that already draws its own
    /// background wants none.
    static func clickable(inset: CGSize, radius: CGFloat = 4) -> ClickableButton {
        ClickableButton(inset: inset, radius: radius)
    }
}

public extension View {

    /// The room `ClickableButton` puts around a label, for the copies of that
    /// label which are not buttons — `MinimalAccountRow` draws two of them, one
    /// for a row with a single period and one hidden to measure the column, and
    /// all three have to come out the same width.
    func padded(by inset: CGSize) -> some View {
        padding(.horizontal, inset.width).padding(.vertical, inset.height)
    }
}

extension View {

    /// The hand, where the system can draw it — see `ClickableButton` for why
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
