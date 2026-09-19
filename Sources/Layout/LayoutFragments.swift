import DOM
import EngineCore
import Style

public struct LayoutFragment: Hashable, Sendable, Codable {
  public var nodeID: NodeID
  public var frame: Rect
  public var contentFrame: Rect
  public var isScrollable: Bool
  public var establishesStacking: Bool
  public var zIndex: Int
  public var opacity: Double

  public init(
    nodeID: NodeID, frame: Rect, contentFrame: Rect, isScrollable: Bool,
    establishesStacking: Bool, zIndex: Int, opacity: Double
  ) {
    self.nodeID = nodeID
    self.frame = frame
    self.contentFrame = contentFrame
    self.isScrollable = isScrollable
    self.establishesStacking = establishesStacking
    self.zIndex = zIndex
    self.opacity = opacity
  }
}

public struct ScrollViewport: Hashable, Sendable, Codable {
  public var nodeID: NodeID
  public var viewport: Rect
  public var contentSize: Size
  public var maxScrollOffset: Point

  public init(nodeID: NodeID, viewport: Rect, contentSize: Size, maxScrollOffset: Point) {
    self.nodeID = nodeID
    self.viewport = viewport
    self.contentSize = contentSize
    self.maxScrollOffset = maxScrollOffset
  }
}

extension LayoutTree {
  public func fragment(for node: NodeID) -> LayoutFragment? {
    guard let box = boxes[node] else { return nil }
    let scrollable =
      box.style.overflowX == .scroll || box.style.overflowX == .auto
      || box.style.overflowY == .scroll || box.style.overflowY == .auto
    let stacking =
      box.style.position != .static || box.style.opacity < 1 || box.style.zIndex != 0
    return LayoutFragment(
      nodeID: node, frame: box.frame, contentFrame: box.contentFrame, isScrollable: scrollable,
      establishesStacking: stacking, zIndex: box.style.zIndex, opacity: box.style.opacity)
  }

  public func fragments() -> [LayoutFragment] {
    paintOrder.compactMap { fragment(for: $0) }
  }

  public func scrollViewports() -> [ScrollViewport] {
    paintOrder.compactMap { id in
      guard let box = boxes[id] else { return nil }
      let horizontal = box.style.overflowX
      let vertical = box.style.overflowY
      let scrolls =
        horizontal == .scroll || horizontal == .auto || vertical == .scroll || vertical == .auto
      guard scrolls else { return nil }
      let content = box.contentFrame.size
      let frame = box.frame
      return ScrollViewport(
        nodeID: id, viewport: frame, contentSize: content,
        maxScrollOffset: Point(
          x: max(0, content.width - frame.width), y: max(0, content.height - frame.height)))
    }
  }

  public func paintOrder(culledTo viewport: Rect) -> [NodeID] {
    paintOrder.filter { id in
      guard let box = boxes[id] else { return false }
      return box.frame.intersects(viewport)
    }
  }
}
