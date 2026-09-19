import Foundation

public struct DirtyRegion: Sendable, Hashable, Codable {
  private var rects: [Rect]
  private var unionRect: Rect?

  public init() {
    rects = []
    unionRect = nil
  }

  public var isEmpty: Bool { rects.isEmpty }
  public var bounds: Rect? { unionRect }
  public var regions: [Rect] { rects }

  public mutating func add(_ rect: Rect) {
    guard !rect.isEmpty else { return }
    unionRect = unionRect.map { $0.union(rect) } ?? rect
    if let index = rects.firstIndex(where: { $0.intersects(rect) }) {
      rects[index] = rects[index].union(rect)
    } else {
      rects.append(rect)
    }
    if rects.count > 32, let unionRect {
      rects = [unionRect]
    }
  }

  public mutating func clear() {
    rects.removeAll(keepingCapacity: true)
    unionRect = nil
  }
}
