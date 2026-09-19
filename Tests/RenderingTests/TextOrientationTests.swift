import Display
import DOM
import EngineCore
import Graphics
import Testing

#if canImport(CoreText)
@Test func textGlyphsAreUprightAndStayInsideTheirDocumentBounds() throws {
  let size = Size(width: 100, height: 120)
  let bounds = Rect(x: 20, y: 10, width: 70, height: 70)
  let list = DisplayList(commands: [.text(DrawTextCommand(
    nodeID: NodeID(index: 1, generation: 1), text: "F", rect: bounds,
    color: .black, fontSize: 48, fontWeight: 400))], size: size)
  let pixels = try SoftwareRenderer().render(list, viewport: size)
  var rows: [(y: Int, right: Int)] = []
  for y in 0..<pixels.height {
    let ink = (0..<pixels.width).filter { pixels.bytes[(y * pixels.width + $0) * 4] < 128 }
    if let right = ink.max() { rows.append((y, right)) }
  }
  #expect(!rows.isEmpty)
  let top = try #require(rows.first)
  let bottom = try #require(rows.last)
  #expect(top.y >= 10 && bottom.y < 80)
  let middle = (top.y + bottom.y) / 2
  let upperReach = rows.filter { $0.y < middle }.map(\.right).max() ?? 0
  let lowerReach = rows.filter { $0.y > middle + 5 }.map(\.right).max() ?? 0
  #expect(upperReach > lowerReach + 5)
}
#endif
