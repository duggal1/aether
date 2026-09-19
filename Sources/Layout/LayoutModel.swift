import DOM
import EngineCore
import Foundation
import Style

public struct LayoutBox: Hashable, Sendable, Codable {
  public var nodeID: NodeID
  public var frame: Rect
  public var contentFrame: Rect
  public var style: ComputedStyle
  public var baseline: Double?

  public init(
    nodeID: NodeID, frame: Rect, contentFrame: Rect, style: ComputedStyle, baseline: Double? = nil
  ) {
    self.nodeID = nodeID
    self.frame = frame
    self.contentFrame = contentFrame
    self.style = style
    self.baseline = baseline
  }
}

public struct LayoutTree: Sendable {
  public var boxes: [NodeID: LayoutBox]
  public var paintOrder: [NodeID]
  public var contentSize: Size
  public var viewport: Size
  public var sourceMutationVersion: UInt64

  public init(
    boxes: [NodeID: LayoutBox], paintOrder: [NodeID], contentSize: Size, viewport: Size,
    sourceMutationVersion: UInt64
  ) {
    self.boxes = boxes
    self.paintOrder = paintOrder
    self.contentSize = contentSize
    self.viewport = viewport
    self.sourceMutationVersion = sourceMutationVersion
  }

  public subscript(_ node: NodeID) -> LayoutBox? { boxes[node] }
}
