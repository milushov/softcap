// Draws one App Store screenshot: a gradient, a caption, and a photograph of
// the app's own window.
//
//     store_shot <window.png> <out.png> <lang> <title> <caption>
//
// 2880×1800, which is one of the four sizes Apple accepts for a Mac screenshot.
// Drawn at 1440×900 points into a 2× bitmap, so every number below is a point
// and the file is Retina.
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
guard arguments.count == 6 else {
    FileHandle.standardError.write(
        "usage: store_shot <window.png> <out.png> <lang> <title> <caption>\n".data(using: .utf8)!)
    exit(2)
}
let windowPath = arguments[1], outPath = arguments[2]
let language = arguments[3], title = arguments[4], caption = arguments[5]

let size = NSSize(width: 1440, height: 900)
let rightToLeft = language == "ar"

guard let window = NSImage(contentsOfFile: windowPath) else {
    FileHandle.standardError.write("store_shot: cannot read \(windowPath)\n".data(using: .utf8)!)
    exit(1)
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

// The gradient the five teasers have always had: blue at the top left, violet
// by the bottom right, with a soft light under the window so the dark chrome
// has something to sit on rather than a flat field.
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.184, green: 0.435, blue: 0.894, alpha: 1),
    NSColor(srgbRed: 0.259, green: 0.341, blue: 0.867, alpha: 1),
    NSColor(srgbRed: 0.416, green: 0.294, blue: 0.847, alpha: 1),
], atLocations: [0, 0.46, 1], colorSpace: .sRGB)!
gradient.draw(in: NSRect(origin: .zero, size: size), angle: -62)

let glow = NSGradient(colors: [
    NSColor(white: 1, alpha: 0.17), NSColor(white: 1, alpha: 0),
], atLocations: [0, 1], colorSpace: .sRGB)!
glow.draw(in: NSRect(x: -160, y: -300, width: 1760, height: 1100), relativeCenterPosition: .zero)

/// Lays out one run of text in the width it is given, centred, in the app's
/// own typeface — and returns how tall it turned out, so the next thing down
/// can start below it.
@discardableResult
func draw(_ text: String, size fontSize: CGFloat, weight: NSFont.Weight,
          top: CGFloat, width: CGFloat, alpha: CGFloat, leading: CGFloat) -> CGFloat {
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
    let bounds = string.boundingRect(
        with: NSSize(width: width, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading])
    let height = ceil(bounds.height)
    // Flipped: the numbers in this file measure down from the top, the way the
    // page they came from does, and AppKit measures up from the bottom.
    string.draw(with: NSRect(x: (size.width - width) / 2, y: size.height - top - height,
                             width: width, height: height),
                options: [.usesLineFragmentOrigin, .usesFontLeading])
    return height
}

let titleHeight = draw(title, size: 74, weight: .bold, top: 52, width: 1180,
                       alpha: 1, leading: language == "hi" || language == "bn" ? 1.24 : 1.04)
draw(caption, size: 30, weight: .regular, top: 52 + titleHeight + 18, width: 1000,
     alpha: 0.93, leading: 1.36)

// The window is never enlarged past its own pixels — the store shows these at
// sizes where a scaled-up screenshot is visibly soft — and never taller than
// the space left under the caption. `window.size` is in points: screencapture
// writes the display's density into the file, so a Retina photograph reports
// half its pixels here and a 1× one all of them, and either is drawn at 1.25×
// at most.
let points = window.size
let scale = min(560 / points.height, 900 / points.width, 1.25)
let drawn = NSSize(width: (points.width * scale).rounded(), height: (points.height * scale).rounded())
let frame = NSRect(x: ((size.width - drawn.width) / 2).rounded(),
                   y: size.height - 300 - drawn.height, width: drawn.width, height: drawn.height)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -26), blur: 46,
                  color: NSColor(srgbRed: 0.047, green: 0.07, blue: 0.235, alpha: 0.42).cgColor)
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
