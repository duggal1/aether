import Foundation

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
      let encoded = NSMutableData()
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
        let destination = CGImageDestinationCreateWithData(
          encoded, UTType.png.identifier as CFString, 1, nil)
      else {
        throw PixelBufferError.encodingFailed
      }
      CGImageDestinationAddImage(destination, image, nil)
      guard CGImageDestinationFinalize(destination) else { throw PixelBufferError.encodingFailed }
      try (encoded as Data).write(to: url, options: .atomic)
    }
  }
#endif

public enum PixelBufferError: Error, Sendable {
  case encodingFailed
}

public enum RendererError: Error, Sendable {
  case unsupported
  case initializationFailed
  case renderingFailed
}
