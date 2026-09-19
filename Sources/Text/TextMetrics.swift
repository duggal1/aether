import EngineCore
import Foundation

public struct TextRunMetrics: Hashable, Sendable, Codable {
  public var size: Size
  public var ascent: Double
  public var descent: Double
  public var leading: Double

  public init(size: Size, ascent: Double, descent: Double, leading: Double = 0) {
    self.size = size
    self.ascent = ascent
    self.descent = descent
    self.leading = leading
  }
}

public protocol TextMeasuring: Sendable {
  func measure(_ text: String, fontSize: Double, fontWeight: Int, maxWidth: Double?)
    -> TextRunMetrics
}
