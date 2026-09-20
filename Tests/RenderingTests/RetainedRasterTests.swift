import Display
import EngineCore
import Graphics
import Testing

@Test func retainedRasterEnforcesBoundsAndReusesOnlyEquivalentFrames() throws {
  var raster = RetainedRaster()
  let list = DisplayList(commands: [.rect(DrawRectCommand(
    rect: Rect(x: 0, y: 0, width: 20, height: 20), color: .black))], size: Size(width: 80, height: 80))
  let size = Size(width: 40, height: 40)
  let first = try raster.render(list, viewport: size, origin: .zero, maximumBytes: 6400)
  #expect(!first.reused)
  #expect(raster.byteCount == 6400)
  #expect(try raster.render(list, viewport: size, origin: .zero, maximumBytes: 6400).reused)
  let shifted = try raster.render(list, viewport: size, origin: Point(x: 0, y: 10), maximumBytes: 6400)
  #expect(!shifted.reused)
  #expect(shifted.pixels != first.pixels)
  #expect(throws: RendererError.self) {
    try raster.render(list, viewport: size, origin: .zero, maximumBytes: 6399)
  }
  #expect(throws: RendererError.self) {
    try raster.render(list, viewport: Size(width: .infinity, height: 1), origin: .zero, maximumBytes: 6400)
  }
  #expect(throws: RendererError.self) {
    try raster.render(list, viewport: size, origin: Point(x: .nan, y: 0), maximumBytes: 6400)
  }
  raster.clear()
  #expect(raster.byteCount == 0)
  #expect(!((try raster.render(list, viewport: size, origin: .zero, maximumBytes: 6400)).reused))
}
