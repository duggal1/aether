import Foundation

public struct Point: Hashable, Sendable, Codable {
  public var x: Double
  public var y: Double

  public init(x: Double = 0, y: Double = 0) {
    self.x = x
    self.y = y
  }

  public static let zero = Point()
}

public struct Size: Hashable, Sendable, Codable {
  public var width: Double
  public var height: Double

  public init(width: Double = 0, height: Double = 0) {
    self.width = width
    self.height = height
  }

  public static let zero = Size()
}

public struct Rect: Hashable, Sendable, Codable {
  public var origin: Point
  public var size: Size

  public init(x: Double = 0, y: Double = 0, width: Double = 0, height: Double = 0) {
    self.origin = Point(x: x, y: y)
    self.size = Size(width: width, height: height)
  }

  public init(origin: Point, size: Size) {
    self.origin = origin
    self.size = size
  }

  public var minX: Double { origin.x }
  public var minY: Double { origin.y }
  public var maxX: Double { origin.x + size.width }
  public var maxY: Double { origin.y + size.height }
  public var width: Double { size.width }
  public var height: Double { size.height }
  public var isEmpty: Bool { width <= 0 || height <= 0 }

  public func contains(_ point: Point) -> Bool {
    point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
  }

  public func intersects(_ other: Rect) -> Bool {
    !(other.maxX <= minX || other.minX >= maxX || other.maxY <= minY || other.minY >= maxY)
  }

  public func intersection(_ other: Rect) -> Rect? {
    guard intersects(other) else { return nil }
    let x1 = max(minX, other.minX)
    let y1 = max(minY, other.minY)
    let x2 = min(maxX, other.maxX)
    let y2 = min(maxY, other.maxY)
    return Rect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
  }

  public func union(_ other: Rect) -> Rect {
    if isEmpty { return other }
    if other.isEmpty { return self }
    let x1 = min(minX, other.minX)
    let y1 = min(minY, other.minY)
    let x2 = max(maxX, other.maxX)
    let y2 = max(maxY, other.maxY)
    return Rect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
  }

  public func inset(by edges: EdgeInsets) -> Rect {
    Rect(
      x: minX + edges.left,
      y: minY + edges.top,
      width: max(0, width - edges.left - edges.right),
      height: max(0, height - edges.top - edges.bottom)
    )
  }

  public func offset(by origin: Point) -> Rect {
    Rect(x: minX - origin.x, y: minY - origin.y, width: width, height: height)
  }
}

public struct EdgeInsets: Hashable, Sendable, Codable {
  public var top: Double
  public var right: Double
  public var bottom: Double
  public var left: Double

  public init(top: Double = 0, right: Double = 0, bottom: Double = 0, left: Double = 0) {
    self.top = top
    self.right = right
    self.bottom = bottom
    self.left = left
  }

  public static let zero = EdgeInsets()

  public var horizontal: Double { left + right }
  public var vertical: Double { top + bottom }
}
