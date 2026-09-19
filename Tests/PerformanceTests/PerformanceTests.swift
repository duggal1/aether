import CSS
import EngineCore
import HTML
import Layout
import Style
import Testing

@Test func tenThousandNodePipelineCompletes() {
  let html = "<body>" + (0..<5_000).map { "<div class='r'>row \($0)</div>" }.joined() + "</body>"
  let clock = ContinuousClock()
  let start = clock.now
  let parsed = HTMLParser.parse(html)
  let sheet = CSSParser.parse(".r{display:block;height:18px}")
  let styled = StyleResolver.resolve(
    document: parsed.document, stylesheets: [sheet], viewport: Size(width: 1280, height: 800))
  let tree = LayoutEngine().layout(styled, viewport: Size(width: 1280, height: 800))
  let elapsed = start.duration(to: clock.now)
  #expect(tree.boxes.count > 5_000)
  #expect(elapsed < .seconds(10))
}
