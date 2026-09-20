// Prints "<windowNumber> <width> <height>" for the largest on-screen window of
// one process, named by pid. `screencapture -R` photographs a rectangle of the
// screen and therefore whatever is in front of the window; `-l<id>` photographs
// the window itself, which is what a screenshot of an accessory app that cannot
// reliably come to the front needs.
//
// By pid and not by name, and this is the whole reason the file changed: the
// screenshot build and the copy in /Applications are both called Softcap, and
// while the installed one had its settings open on the Updates pane, the
// largest window named Softcap was that one — fifty pictures of it, in five
// languages' worth of gradients, before anybody looked.
import CoreGraphics
import Foundation

guard CommandLine.arguments.count > 1, let wanted = pid_t(CommandLine.arguments[1]) else {
    FileHandle.standardError.write("usage: window_id <pid>\n".data(using: .utf8)!)
    exit(2)
}
guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                            kCGNullWindowID) as? [[String: Any]] else {
    exit(2)
}
var best: (number: Int, width: Double, height: Double)? = nil
for window in list {
    guard let owner = window[kCGWindowOwnerPID as String] as? pid_t, owner == wanted,
          let number = window[kCGWindowNumber as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? Double, let height = bounds["Height"] as? Double,
          let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
          width > 120, height > 120
    else { continue }
    if best == nil || width * height > best!.width * best!.height {
        best = (number, width, height)
    }
}
guard let found = best else { exit(1) }
print("\(found.number) \(Int(found.width)) \(Int(found.height))")
