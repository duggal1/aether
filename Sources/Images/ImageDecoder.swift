import Foundation

#if canImport(ImageIO) && canImport(CoreGraphics)
  import ImageIO
  import CoreGraphics

  public enum ImageDecoder {
    public static func decode(_ data: Data) throws -> DecodedImage {
      guard let source = CGImageSourceCreateWithData(data as CFData, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
      else { throw ImageError.decodingFailed }
      let width = image.width
      let height = image.height
      var rgba = [UInt8](repeating: 0, count: width * height * 4)
      guard
        let context = CGContext(
          data: &rgba,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: width * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
      else { throw ImageError.decodingFailed }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return DecodedImage(width: width, height: height, rgba: rgba)
    }
  }
#else
  public enum ImageDecoder {
    public static func decode(_ data: Data) throws -> DecodedImage {
      throw ImageError.unsupported
    }
  }
#endif
