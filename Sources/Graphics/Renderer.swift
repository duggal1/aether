import Display
import EngineCore
import Foundation

public protocol OffscreenRendering: Sendable {
  func render(_ displayList: DisplayList, viewport: Size) throws -> PixelBuffer
}

public enum RendererError: Error, Sendable {
  case unsupported
  case initializationFailed
  case renderingFailed
}
