import AppKit

/// The menu bar glyph: the same two rings as the app icon, drawn monochrome.
///
/// Not an SF Symbol. A stock symbol would not match the icon, and the menu bar
/// is where people learn to recognise this app — the two shapes should be the
/// same shape.
///
/// Rendered as a template image so the system tints it: white on a dark menu
/// bar, black on a light one, dimmed when the bar is inactive.
enum MenuBarGlyph {
    /// Points, not pixels: the system asks for the right scale itself.
    static func image(side: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            let center = CGPoint(x: rect.midX, y: rect.midY)
            let lineWidth = side * 0.125

            // Outer ring: full circle at low opacity, then the filled part.
            arc(context, center: center, radius: side * 0.335, width: lineWidth,
                fraction: 1, alpha: 0.35)
            arc(context, center: center, radius: side * 0.335, width: lineWidth,
                fraction: 0.65, alpha: 1)

            // Inner ring, drawn only when there is room for it.
            //
            // The menu bar hands out 16 pt, where an inner ring would be about
            // two points across with a two-point stroke — a dot, not a ring.
            // Checked on a screenshot: it read as a smudge inside the outer
            // ring. One clean ring beats two mushed together, so the threshold
            // sits above the menu bar size on purpose.
            if side >= 22 {
                arc(context, center: center, radius: side * 0.135, width: lineWidth * 0.8,
                    fraction: 1, alpha: 0.35)
                arc(context, center: center, radius: side * 0.135, width: lineWidth * 0.8,
                    fraction: 0.30, alpha: 1)
            }
            return true
        }
        // The template flag is what lets the system invert it for a light bar.
        image.isTemplate = true
        return image
    }

    private static func arc(_ context: CGContext, center: CGPoint, radius: CGFloat,
                            width: CGFloat, fraction: CGFloat, alpha: CGFloat) {
        context.saveGState()
        context.setStrokeColor(NSColor.black.withAlphaComponent(alpha).cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        let start = CGFloat.pi / 2                    // twelve o'clock
        context.addArc(center: center, radius: radius,
                       startAngle: start, endAngle: start - fraction * 2 * .pi,
                       clockwise: true)
        context.strokePath()
        context.restoreGState()
    }
}
