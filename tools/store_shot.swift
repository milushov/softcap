// Draws one App Store screenshot: a gradient, a caption, and a photograph of
// the app's own window.
//
//     store_shot <window.png> <out.png> <screen> <lang> <headline> <caption>
//
// 2880×1800, which is one of the four sizes Apple accepts for a Mac screenshot.
// Drawn at 1440×900 points into a 2× bitmap, so every number below is a point
// and the file is Retina.
//
// The design is the five teasers that were on the store before the listing was
// localised, measured from the images in docs/screenshots: each screen has a
// gradient of its own, a one-word headline, a caption held to two lines, and the
// window in the lower two thirds at the size the original showed it. The five
// were one at first — the blue one, copied five times — and that was noticed on
// the store page, where the five sit side by side and read as one picture.
//
// AppKit rather than a browser or an image library, for the text. This is
// written ten times, once per language: Arabic has to shape its letters and run
// right to left, Hindi and Bengali have to assemble their conjuncts, Chinese
// needs a font that has the glyphs at all. Core Text does all of that, and it
// is the same engine that draws the window in the picture — so the caption and
// the app cannot disagree about how a language looks. A browser would also do
// it, and the first version of this did: headless Chrome hung on the second
// image and then exited 21 on the third, with the diagnosis costing more than
// the whole of this file.

import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 7 else {
    FileHandle.standardError.write(
        "usage: store_shot <window.png> <out.png> <screen> <lang> <headline> <caption>\n"
            .data(using: .utf8)!)
    exit(2)
}
let windowPath = arguments[1], outPath = arguments[2], screen = arguments[3]
let language = arguments[4], headline = arguments[5], caption = arguments[6]

let size = NSSize(width: 1440, height: 900)
let rightToLeft = language == "ar"

/// The five backgrounds, sampled along the diagonal of the originals at 2%,
/// 26%, 50%, 74% and 98% — a copy of each, not an impression of it.
let palettes: [String: [String]] = [
    "01-limits":        ["216eea", "2766e7", "4a40dc", "5139da", "5a2fd6"],
    "02-accounts":      ["cf2e82", "d63971", "f16537", "f76e28", "fd781a"],
    "03-notifications": ["1e8d48", "1b8845", "136a3a", "116338", "105d35"],
    "04-statistics":    ["0b6fa8", "0c7baa", "10aaaf", "12b5ae", "14c1b4"],
    "05-minimal":       ["394958", "324251", "1d242d", "171d24", "12151b"],
]

guard let palette = palettes[screen] else {
    FileHandle.standardError.write(
        "store_shot: no background for \(screen); it has \(palettes.keys.sorted())\n".data(using: .utf8)!)
    exit(2)
}
guard let window = NSImage(contentsOfFile: windowPath) else {
    FileHandle.standardError.write("store_shot: cannot read \(windowPath)\n".data(using: .utf8)!)
    exit(1)
}

func colour(_ hex: String) -> NSColor {
    let value = UInt32(hex, radix: 16)!
    return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                   green: CGFloat((value >> 8) & 0xFF) / 255,
                   blue: CGFloat(value & 0xFF) / 255, alpha: 1)
}

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width) * 2, pixelsHigh: Int(size.height) * 2,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
rep.size = size

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let context = NSGraphicsContext.current!.cgContext

// Top left to bottom right, and nothing else on it. A radial light under the
// window was tried and is the reason this comment exists: `NSGradient` draws a
// radial fill out to the corners of the rectangle it is given, so along the
// rectangle's edges the light had not yet faded to nothing, and the edge showed
// as a line a hundred points from the top of every picture.
let gradient = NSGradient(colors: palette.map(colour),
                          atLocations: [0, 0.26, 0.5, 0.74, 1], colorSpace: .sRGB)!
gradient.draw(in: NSRect(origin: .zero, size: size), angle: -atan2(size.height, size.width) * 180 / .pi)

func height(of string: NSAttributedString, in width: CGFloat) -> CGFloat {
    ceil(string.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                             options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
}

/// The narrowest column that holds the text in as many lines as `width` does.
///
/// Core Text fills each line as far as it can and leaves the remainder on the
/// last, so a caption that needs two lines comes out as one long line and one
/// word — `…accounts in` / `one list.` Narrowing the column until the line count
/// would rise again is what balances them, and it costs nothing in a
/// centred layout.
func balanced(_ string: NSAttributedString, within width: CGFloat) -> CGFloat {
    let lines = height(of: string, in: width)
    var narrow = width
    while narrow - 6 > width / 2, height(of: string, in: narrow - 6) == lines {
        narrow -= 6
    }
    return narrow
}

/// Lays out one run of text in the width it is given, centred, in the app's
/// own typeface — and returns how tall it turned out, so the next thing down
/// can start below it.
@discardableResult
func draw(_ text: String, size fontSize: CGFloat, weight: NSFont.Weight,
          top: CGFloat, width maxWidth: CGFloat, alpha: CGFloat, leading: CGFloat,
          balance: Bool = false) -> CGFloat {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    // Set from the language rather than left to `.natural`, which reads the
    // first strong character: an Arabic caption that opens with `Claude` would
    // be laid out left to right and its full stop would land at the wrong end.
    paragraph.baseWritingDirection = rightToLeft ? .rightToLeft : .leftToRight
    paragraph.lineHeightMultiple = leading

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
        .foregroundColor: NSColor(white: 1, alpha: alpha),
        .paragraphStyle: paragraph,
        .kern: weight == .bold ? -fontSize * 0.022 : 0,
    ]
    let string = NSAttributedString(string: text, attributes: attributes)
    let width = balance ? balanced(string, within: maxWidth) : maxWidth
    let height = height(of: string, in: width)
    // Flipped: the numbers in this file measure down from the top, the way the
    // originals were measured, and AppKit measures up from the bottom.
    string.draw(with: NSRect(x: (size.width - width) / 2, y: size.height - top - height,
                             width: width, height: height),
                options: [.usesLineFragmentOrigin, .usesFontLeading])
    return height
}

// One word at 74, then the caption at 28 in a column narrow enough that every
// language's sentence breaks into two lines the way the originals' did — a
// single long line reads as a subtitle, two short ones as a caption.
let headlineHeight = draw(headline, size: 74, weight: .bold, top: 46, width: 1180,
                          alpha: 1, leading: language == "hi" || language == "bn" ? 1.24 : 1.04)
draw(caption, size: 28, weight: .regular, top: 46 + headlineHeight + 14, width: 470,
     alpha: 0.96, leading: 1.32, balance: true)

// The window fits a box the size of the settings window — 720 by 502 points,
// which the settings window therefore fills at exactly 1× — and the two smaller
// windows are enlarged to fit it, to twice their size at most: the minimal
// window is a third of that width and would be a stamp in the corner at 1×,
// and it was drawn at 2× in the original. `window.size` is in points:
// screencapture writes the display's density into the file, so a Retina
// photograph reports half its pixels here and a 1× one all of them.
let box = NSSize(width: 720, height: 502)
let points = window.size
let scale = min(box.height / points.height, box.width / points.width, 2)
let drawn = NSSize(width: (points.width * scale).rounded(), height: (points.height * scale).rounded())
// Centred in the box, whose top is 275 points down — the settings window's own
// place in the originals; a shorter window sits in the middle of that band.
let top = 275 + (box.height - drawn.height) / 2
let frame = NSRect(x: ((size.width - drawn.width) / 2).rounded(),
                   y: (size.height - top - drawn.height).rounded(),
                   width: drawn.width, height: drawn.height)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -22), blur: 40,
                  color: NSColor(white: 0, alpha: 0.38).cgColor)
window.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
context.restoreGState()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
do {
    try png.write(to: URL(fileURLWithPath: outPath))
} catch {
    FileHandle.standardError.write("store_shot: cannot write \(outPath): \(error)\n".data(using: .utf8)!)
    exit(1)
}
