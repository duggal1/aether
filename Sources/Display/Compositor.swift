import DOM
import EngineCore

public struct CompositorLayer: Hashable, Sendable, Codable {
  public var nodeID: NodeID
  public var frame: Rect
  public var opacity: Double
  public var zIndex: Int
  public var scrollOffset: Point
  public var contentSize: Size
  public var contentVersion: UInt64
  public var isScrollable: Bool

  public init(
    nodeID: NodeID, frame: Rect, opacity: Double, zIndex: Int, scrollOffset: Point,
    contentSize: Size, contentVersion: UInt64, isScrollable: Bool
  ) {
    self.nodeID = nodeID
    self.frame = frame
    self.opacity = opacity
    self.zIndex = zIndex
    self.scrollOffset = scrollOffset
    self.contentSize = contentSize
    self.contentVersion = contentVersion
    self.isScrollable = isScrollable
  }
}

public struct ScrollResult: Hashable, Sendable, Codable {
  public var offset: Point
  public var damage: DirtyRegion

  public init(offset: Point, damage: DirtyRegion) {
    self.offset = offset
    self.damage = damage
  }
}

public struct RetainedCompositor: Hashable, Sendable, Codable {
  public private(set) var layers: [NodeID: CompositorLayer]
  public private(set) var damage: DirtyRegion

  public init(layers: [NodeID: CompositorLayer] = [:]) {
    self.layers = layers
    self.damage = DirtyRegion()
  }

  public static func isCompositeOnly(
    from old: [NodeID: CompositorLayer], to next: [NodeID: CompositorLayer]
  ) -> Bool {
    guard Set(old.keys) == Set(next.keys) else { return false }
    for (id, current) in old {
      guard let updated = next[id] else { return false }
      if current.frame != updated.frame { return false }
      if current.zIndex != updated.zIndex { return false }
      if current.contentVersion != updated.contentVersion { return false }
    }
    return true
  }

  public mutating func commit(_ next: [NodeID: CompositorLayer]) -> Bool {
    let compositeOnly = Self.isCompositeOnly(from: layers, to: next)
    if !compositeOnly {
      for (id, layer) in next {
        guard let current = layers[id] else {
          damage.add(layer.frame)
          continue
        }
        if current.frame != layer.frame {
          damage.add(current.frame)
          damage.add(layer.frame)
        } else if current != layer {
          damage.add(layer.frame)
        }
      }
      for (id, layer) in layers where next[id] == nil {
        damage.add(layer.frame)
      }
    }
    layers = next
    return compositeOnly
  }

  public mutating func scroll(_ id: NodeID, by delta: Point) -> ScrollResult? {
    guard var layer = layers[id], layer.isScrollable else { return nil }
    let maxX = max(0, layer.contentSize.width - layer.frame.width)
    let maxY = max(0, layer.contentSize.height - layer.frame.height)
    let next = Point(
      x: min(maxX, max(0, layer.scrollOffset.x + delta.x)),
      y: min(maxY, max(0, layer.scrollOffset.y + delta.y)))
    let moved = Point(x: next.x - layer.scrollOffset.x, y: next.y - layer.scrollOffset.y)
    layer.scrollOffset = next
    layers[id] = layer
    var exposed = DirtyRegion()
    let frame = layer.frame
    if moved.x != 0 {
      let width = min(abs(moved.x), frame.width)
      exposed.add(
        Rect(
          x: moved.x > 0 ? frame.maxX - width : frame.minX,
          y: frame.minY, width: width, height: frame.height))
    }
    if moved.y != 0 {
      let height = min(abs(moved.y), frame.height)
      exposed.add(
        Rect(
          x: frame.minX, y: moved.y > 0 ? frame.maxY - height : frame.minY,
          width: frame.width, height: height))
    }
    for rect in exposed.regions { damage.add(rect) }
    return ScrollResult(offset: next, damage: exposed)
  }

  public mutating func takeDamage() -> DirtyRegion {
    let taken = damage
    damage.clear()
    return taken
  }
}
