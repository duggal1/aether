import BrowserEngine
import CSS
import DOM
import EngineCore
import Foundation
import HTML
import Layout
import Style
import Text

@main
struct EngineBench {
  static func main() async {
    let count = 10_000
    let body = (0..<count).map {
      "<div class=\"row\"><span>Item \($0)</span><a href=\"/\($0)\">Open</a></div>"
    }.joined()
    let html =
      "<html><head><style>.row{display:flex;gap:8px;padding:2px}a{color:#04d123}</style></head><body>\(body)</body></html>"
    let clock = ContinuousClock()

    let parseStart = clock.now
    let parsed = HTMLParser.parse(html)
    let parse = parseStart.duration(to: clock.now)

    let css = CSSParser.parse(".row{display:flex;gap:8px;padding:2px}a{color:#04d123}")
    let styleStart = clock.now
    let styled = StyleResolver.resolve(
      document: parsed.document, stylesheets: [css], viewport: Size(width: 1440, height: 900))
    let style = styleStart.duration(to: clock.now)

    let layoutStart = clock.now
    let tree = LayoutEngine().layout(styled, viewport: Size(width: 1440, height: 900))
    let layout = layoutStart.duration(to: clock.now)

    print("nodes=\(parsed.document.nodeCount)")
    print("parse_ms=\(milliseconds(parse))")
    print("style_ms=\(milliseconds(style))")
    print("layout_ms=\(milliseconds(layout))")
    print("boxes=\(tree.boxes.count)")
  }

  static func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
  }
}
