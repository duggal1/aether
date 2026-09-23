import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2,
  let frontmost = NSWorkspace.shared.frontmostApplication,
  frontmost.bundleIdentifier == CommandLine.arguments[1],
  let windows = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
  exit(1)
}

for window in windows {
  guard let owner = window[kCGWindowOwnerPID as String] as? NSNumber,
    owner.int32Value == frontmost.processIdentifier,
    let layer = window[kCGWindowLayer as String] as? NSNumber,
    layer.intValue == 0,
    let bounds = window[kCGWindowBounds as String] as? [String: Any],
    let width = bounds["Width"] as? NSNumber,
    let height = bounds["Height"] as? NSNumber,
    width.doubleValue > 200,
    height.doubleValue > 200,
    let number = window[kCGWindowNumber as String] as? NSNumber else { continue }
  print(number.uint32Value)
  exit(0)
}

exit(1)
