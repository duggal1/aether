#!/bin/zsh
set -euo pipefail
repo_dir="${0:A:h:h}"
cd "$repo_dir"
icon_source_dir=Sources/BrowserUI/Sources/icons
icon_output=Sources/AetherApp/Resources/AetherIcon.icns
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat > "$work/main.swift" <<'SWIFT'
import AppKit
import SwiftUI

@main
struct AetherIconExport {
  @MainActor static func main() {
    let sizes: [(String, CGFloat)] = [
      ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
      ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256),
      ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]
    guard CommandLine.arguments.count > 1 else { exit(64) }
    let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    for (name, side) in sizes {
      do {
        try AetherAppIconImage.writePNG(side: side, to: directory.appendingPathComponent("\(name).png"))
      } catch {
        FileHandle.standardError.write(Data("icon export failed: \(name)\n".utf8))
        exit(1)
      }
    }
  }
}
SWIFT
iconset="$work/AetherIcon.iconset"
mkdir -p "$iconset"
swiftc -O -parse-as-library "$work/main.swift" \
  "$icon_source_dir/favicon.swift" "$icon_source_dir/AetherAppIcon.swift" \
  -o "$work/aether-icons"
"$work/aether-icons" "$iconset"
iconutil -c icns "$iconset" -o "$icon_output"
print "$icon_output"
