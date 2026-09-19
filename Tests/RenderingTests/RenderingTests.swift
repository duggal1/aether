import CSS
import DOM
import Display
import EngineCore
import Graphics
import HTML
import Images
import Layout
import Style
import Testing

@Test func softwareRendererProducesExpectedSurface() throws {
  let document = HTMLParser.parse("<body><div class='box'>x</div></body>").document
  let sheet = CSSParser.parse(
    "body{display:block}.box{display:block;background:#ff0000;width:100px;height:50px}")
  let styled = StyleResolver.resolve(
    document: document, stylesheets: [sheet], viewport: Size(width: 320, height: 240))
  let layout = LayoutEngine().layout(styled, viewport: Size(width: 320, height: 240))
  let display = DisplayListBuilder.build(document: document, layout: layout)
  let pixels = try SoftwareRenderer().render(display, viewport: Size(width: 320, height: 240))
  #expect(pixels.width == 320)
  #expect(pixels.height == 240)
  #expect(pixels.bytes.count == 320 * 240 * 4)
}

@Test func softwareRendererCompositesDecodedImages() throws {
  let image = DecodedImage(width: 2, height: 1, rgba: [255, 0, 0, 255, 0, 255, 0, 255])
  let list = DisplayList(
    commands: [
      .image(
        DrawImageCommand(
          nodeID: NodeID(index: 1, generation: 1),
          image: image,
          rect: Rect(x: 0, y: 0, width: 4, height: 2)
        ))
    ], size: Size(width: 4, height: 2))
  let pixels = try SoftwareRenderer().render(list, viewport: Size(width: 4, height: 2))

  #expect(pixels.bytes[0] == 255)
  #expect(pixels.bytes[1] == 0)
  let right = 3 * 4
  #expect(pixels.bytes[right] == 0)
  #expect(pixels.bytes[right + 1] == 255)
}
