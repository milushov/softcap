#!/usr/bin/env swift
//
// Generates the app icon at every size the platforms ask for.
//
// The icon is drawn in code rather than stored as exported images: that way a
// change is a one-line edit and a re-run, and the rule for small sizes lives
// next to the drawing instead of in someone's memory.
//
//   swift tools/make_icons.swift <output-directory>
//
import AppKit

// MARK: - design

/// Graphite background. Dark enough that the accent reads on it in both light
/// and dark docks.
let ink = NSColor(srgbRed: 0.110, green: 0.110, blue: 0.133, alpha: 1)
/// The single accent. Everything else is white at reduced opacity.
let accent = NSColor(srgbRed: 0.204, green: 0.780, blue: 0.349, alpha: 1)

/// How full each ring is drawn. Fixed values, not live data: the icon sits in
/// the Dock even when the app is closed, so a changing icon would lie.
let weeklyFill = 0.65
let sessionFill = 0.30

/// Below this pixel size the inner ring is dropped and the outer one thickened.
/// Two concentric strokes cannot be told apart once a ring is a few pixels
/// across — they merge into a smudge. Better one honest ring than two mushed.
let innerRingCutoff = 40

func drawIcon(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext

    let side = CGFloat(size)
    let center = CGPoint(x: side / 2, y: side / 2)

    // Rounded square. macOS icons carry their own shape; iOS masks it anyway,
    // so drawing it here is correct on both.
    let corner = side * 0.2237   // the Apple squircle ratio, near enough
    let plate = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: side, height: side),
                             xRadius: corner, yRadius: corner)
    ink.setFill()
    plate.fill()

    let small = size < innerRingCutoff

    // Outer ring — the weekly window.
    let outerRadius = side * (small ? 0.30 : 0.307)
    let outerWidth = side * (small ? 0.135 : 0.0795)
    ring(context, center: center, radius: outerRadius, width: outerWidth,
         fraction: 1, color: NSColor.white.withAlphaComponent(0.22), rounded: !small)
    ring(context, center: center, radius: outerRadius, width: outerWidth,
         fraction: weeklyFill, color: accent, rounded: !small)

    // Inner ring — the five-hour window. Dropped at small sizes.
    if !small {
        let innerRadius = side * 0.159
        let innerWidth = side * 0.0795
        ring(context, center: center, radius: innerRadius, width: innerWidth,
             fraction: 1, color: NSColor.white.withAlphaComponent(0.22), rounded: true)
        ring(context, center: center, radius: innerRadius, width: innerWidth,
             fraction: sessionFill, color: .white, rounded: true)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Draws an arc starting at twelve o'clock and running clockwise, the way a
/// filling gauge reads.
func ring(_ context: CGContext, center: CGPoint, radius: CGFloat, width: CGFloat,
          fraction: Double, color: NSColor, rounded: Bool) {
    guard fraction > 0 else { return }
    context.saveGState()
    context.setStrokeColor(color.cgColor)
    context.setLineWidth(width)
    context.setLineCap(rounded ? .round : .butt)

    let start = CGFloat.pi / 2                       // twelve o'clock
    let end = start - CGFloat(fraction) * 2 * .pi    // clockwise
    context.addArc(center: center, radius: radius,
                   startAngle: start, endAngle: end, clockwise: true)
    context.strokePath()
    context.restoreGState()
}

// MARK: - output

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: make_icons.swift <output-directory>\n".utf8))
    exit(1)
}
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

/// Every size both platforms ask for, deduplicated.
let sizes = [16, 32, 64, 128, 256, 512, 1024]

for size in sizes {
    let rep = drawIcon(size: size)
    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    let url = outputDirectory.appendingPathComponent("icon_\(size).png")
    try? data.write(to: url)
    print("  \(url.lastPathComponent)")
}
print("done: \(sizes.count) sizes")
