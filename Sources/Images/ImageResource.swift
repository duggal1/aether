import EngineCore
import Foundation

public struct DecodedImage: Hashable, Sendable, Codable {
  public var width: Int
  public var height: Int
  public var rgba: [UInt8]

  public init(width: Int, height: Int, rgba: [UInt8]) {
    self.width = max(0, width)
    self.height = max(0, height)
    self.rgba = rgba
  }

  public var size: Size { Size(width: Double(width), height: Double(height)) }
  public var isValid: Bool { width > 0 && height > 0 && rgba.count >= width * height * 4 }
}

public enum ImageError: Error, Sendable {
  case unsupported
  case decodingFailed
}
