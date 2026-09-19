import Display
import EngineCore
import Foundation
import Images

#if canImport(CoreGraphics) && canImport(CoreText)
  import CoreGraphics
  import CoreText
#endif

public struct SoftwareRenderer: OffscreenRendering {
  public init() {}

  public func render(_ displayList: DisplayList, viewport: Size) throws -> PixelBuffer {
    try render(displayList, viewport: viewport, origin: .zero)
  }

  public func render(_ displayList: DisplayList, viewport: Size, origin: Point)
    throws -> PixelBuffer
  {
    let width = max(1, Int(ceil(viewport.width)))
    let height = max(1, Int(ceil(viewport.height)))
    var buffer = PixelBuffer(width: width, height: height, fill: .white)
    var clips: [Rect] = [Rect(x: 0, y: 0, width: viewport.width, height: viewport.height)]

    for command in displayList.commands {
      switch command {
      case .rect(let rect):
        var shifted = rect
        shifted.rect = shifted.rect.offset(by: origin)
        let target = clipped(shifted.rect, by: clips.last)
        if let target { buffer.blend(rect: target, color: shifted.color, opacity: shifted.opacity) }
      case .text(let text):
        var shifted = text
        shifted.rect = shifted.rect.offset(by: origin)
        #if canImport(CoreGraphics) && canImport(CoreText)
          drawText(shifted, into: &buffer, clip: clips.last)
        #else
          drawFallbackText(shifted, into: &buffer, clip: clips.last)
        #endif
      case .image(let image):
        var shifted = image
        shifted.rect = shifted.rect.offset(by: origin)
        buffer.blend(
          image: shifted.image, in: shifted.rect, clip: clips.last, opacity: shifted.opacity)
      case .pushClip(let clip):
        let shifted = clip.rect.offset(by: origin)
        if let current = clips.last, let intersection = current.intersection(shifted) {
          clips.append(intersection)
        } else {
          clips.append(Rect())
        }
      case .popClip:
        if clips.count > 1 { clips.removeLast() }
      }
    }
    return buffer
  }

  private func clipped(_ rect: Rect, by clip: Rect?) -> Rect? {
    guard let clip else { return rect }
    return rect.intersection(clip)
  }

  private func drawFallbackText(
    _ command: DrawTextCommand, into buffer: inout PixelBuffer, clip: Rect?
  ) {
    let glyphWidth = max(1, command.fontSize * 0.48)
    let glyphHeight = max(1, command.fontSize * 0.72)
    var x = command.rect.minX
    var y = command.rect.minY + command.fontSize * 0.2
    for character in command.text {
      if character == "\n" || x + glyphWidth > command.rect.maxX {
        x = command.rect.minX
        y += command.fontSize * 1.2
        if character == "\n" { continue }
      }
      if !character.isWhitespace {
        let rect = Rect(x: x, y: y, width: glyphWidth * 0.72, height: glyphHeight)
        if let target = clipped(rect, by: clip) {
          buffer.blend(rect: target, color: command.color, opacity: command.opacity)
        }
      }
      x += glyphWidth
    }
  }

  #if canImport(CoreGraphics) && canImport(CoreText)
    private func drawText(_ command: DrawTextCommand, into buffer: inout PixelBuffer, clip: Rect?) {
      var bytes = buffer.bytes
      guard
        let context = CGContext(
          data: &bytes,
          width: buffer.width,
          height: buffer.height,
          bitsPerComponent: 8,
          bytesPerRow: buffer.width * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
      else { return }
      context.translateBy(x: 0, y: CGFloat(buffer.height))
      context.scaleBy(x: 1, y: -1)
      if let clip {
        context.clip(to: CGRect(x: clip.minX, y: clip.minY, width: clip.width, height: clip.height))
      }
      let weight = CGFloat(min(1, max(-1, Double(command.fontWeight - 400) / 500)))
      let descriptor = CTFontDescriptorCreateWithAttributes(
        [
          kCTFontTraitsAttribute: [kCTFontWeightTrait: weight] as CFDictionary
        ] as CFDictionary)
      let font = CTFontCreateWithFontDescriptor(descriptor, CGFloat(command.fontSize), nil)
      let color = CGColor(
        red: command.color.red, green: command.color.green, blue: command.color.blue,
        alpha: command.color.alpha * command.opacity)
      let attributed = NSAttributedString(
        string: command.text,
        attributes: [
          NSAttributedString.Key(kCTFontAttributeName as String): font,
          NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ])
      let framesetter = CTFramesetterCreateWithAttributedString(attributed)
      let path = CGMutablePath()
      path.addRect(
        CGRect(
          x: command.rect.minX, y: command.rect.minY, width: command.rect.width,
          height: command.rect.height))
      let frame = CTFramesetterCreateFrame(
        framesetter, CFRange(location: 0, length: attributed.length), path, nil)
      CTFrameDraw(frame, context)
      buffer.bytes = bytes
    }
  #endif
}
