import Display
import EngineCore
import Graphics
import Testing

@Test func softwareRendererPreservesOffscreenRenderingContract() throws {
  let renderer: any OffscreenRendering = SoftwareRenderer()
  let image = try renderer.render(DisplayList(), viewport: Size(width: 10, height: 10))
  #expect(image.width == 10)
  #expect(image.height == 10)
}
