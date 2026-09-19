import EngineCore
import Foundation
import Images

public struct PixelBuffer: Hashable, Sendable {
  public let width: Int
  public let height: Int
  public var bytes: [UInt8]

  public init(width: Int, height: Int, fill: RGBAColor = .white) {
    self.width = max(1, width)
    self.height = max(1, height)
    let color = fill.rgba8
    var storage = [UInt8](repeating: 0, count: self.width * self.height * 4)
    for offset in stride(from: 0, to: storage.count, by: 4) {
      storage[offset] = color.0
      storage[offset + 1] = color.1
      storage[offset + 2] = color.2
      storage[offset + 3] = color.3
    }
    bytes = storage
  }

  public mutating func blend(rect: Rect, color: RGBAColor, opacity: Double = 1) {
    let x0 = max(0, Int(floor(rect.minX)))
    let y0 = max(0, Int(floor(rect.minY)))
    let x1 = min(width, Int(ceil(rect.maxX)))
    let y1 = min(height, Int(ceil(rect.maxY)))
    guard x0 < x1, y0 < y1 else { return }
    let source = color.rgba8
    let alpha = min(1, max(0, color.alpha * opacity))
    for y in y0..<y1 {
      for x in x0..<x1 {
        let i = (y * width + x) * 4
        let inverse = 1 - alpha
        bytes[i] = UInt8(min(255, Double(source.0) * alpha + Double(bytes[i]) * inverse))
        bytes[i + 1] = UInt8(min(255, Double(source.1) * alpha + Double(bytes[i + 1]) * inverse))
        bytes[i + 2] = UInt8(min(255, Double(source.2) * alpha + Double(bytes[i + 2]) * inverse))
        bytes[i + 3] = 255
      }
    }
  }

  public mutating func blend(
    image: DecodedImage, in rect: Rect, clip: Rect? = nil, opacity: Double = 1
  ) {
    guard image.isValid, rect.width > 0, rect.height > 0 else { return }
    let visible = clip.flatMap { rect.intersection($0) } ?? rect
    let x0 = max(0, Int(floor(visible.minX)))
    let y0 = max(0, Int(floor(visible.minY)))
    let x1 = min(width, Int(ceil(visible.maxX)))
    let y1 = min(height, Int(ceil(visible.maxY)))
    guard x0 < x1, y0 < y1 else { return }
    let globalOpacity = min(1, max(0, opacity))

    for y in y0..<y1 {
      let v = min(0.999999, max(0, (Double(y) + 0.5 - rect.minY) / rect.height))
      let sourceY = min(image.height - 1, max(0, Int(v * Double(image.height))))
      for x in x0..<x1 {
        let u = min(0.999999, max(0, (Double(x) + 0.5 - rect.minX) / rect.width))
        let sourceX = min(image.width - 1, max(0, Int(u * Double(image.width))))
        let sourceIndex = (sourceY * image.width + sourceX) * 4
        let targetIndex = (y * width + x) * 4
        let sourceAlpha = Double(image.rgba[sourceIndex + 3]) / 255 * globalOpacity
        let inverse = 1 - sourceAlpha
        bytes[targetIndex] = UInt8(
          min(
            255,
            Double(image.rgba[sourceIndex]) * sourceAlpha + Double(bytes[targetIndex]) * inverse))
        bytes[targetIndex + 1] = UInt8(
          min(
            255,
            Double(image.rgba[sourceIndex + 1]) * sourceAlpha + Double(bytes[targetIndex + 1])
              * inverse))
        bytes[targetIndex + 2] = UInt8(
          min(
            255,
            Double(image.rgba[sourceIndex + 2]) * sourceAlpha + Double(bytes[targetIndex + 2])
              * inverse))
        bytes[targetIndex + 3] = 255
      }
    }
  }

  public func ppmData() -> Data {
    var data = Data("P6\n\(width) \(height)\n255\n".utf8)
    data.reserveCapacity(data.count + width * height * 3)
    for i in stride(from: 0, to: bytes.count, by: 4) {
      data.append(bytes[i])
      data.append(bytes[i + 1])
      data.append(bytes[i + 2])
    }
    return data
  }

  public func write(to url: URL) throws {
    #if canImport(CoreGraphics) && canImport(ImageIO)
      if url.pathExtension.lowercased() == "png" {
        try writePNG(to: url)
        return
      }
    #endif
    try ppmData().write(to: url, options: .atomic)
  }
}

#if canImport(CoreGraphics) && canImport(ImageIO)
  import CoreGraphics
  import ImageIO
  import UniformTypeIdentifiers

  extension PixelBuffer {
    private func writePNG(to url: URL) throws {
      var mutable = bytes
      guard
        let context = CGContext(
          data: &mutable,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: width * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(
          url as CFURL, UTType.png.identifier as CFString, 1, nil)
      else {
        throw PixelBufferError.encodingFailed
      }
      CGImageDestinationAddImage(destination, image, nil)
      guard CGImageDestinationFinalize(destination) else { throw PixelBufferError.encodingFailed }
    }
  }
#endif

public enum PixelBufferError: Error, Sendable {
  case encodingFailed
}
