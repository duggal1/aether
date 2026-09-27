import EngineCore
import Foundation

public enum AgentInteractionKind: String, Sendable, Equatable, Codable {
  case move
  case hover
  case pointer
  case click
  case dragging
  case typing
  case scrolling
  case idle
}

/// An observation of an operation issued through the browser runtime. Points are
/// WebKit client coordinates (CSS pixels), relative to the page viewport.
public struct AgentInteractionUpdate: Sendable, Equatable, Codable {
  public let sequence: UInt64
  public let pageID: PageID
  public let kind: AgentInteractionKind
  public let point: Point?
  public let viewport: Size?
  public let targetLuminance: Double?
  public let movementDuration: Double

  public init(sequence: UInt64, pageID: PageID, kind: AgentInteractionKind,
              point: Point? = nil, viewport: Size? = nil, targetLuminance: Double? = nil,
              movementDuration: Double = 0) {
    self.sequence = sequence
    self.pageID = pageID
    self.kind = kind
    self.point = point
    self.viewport = viewport
    self.targetLuminance = targetLuminance
    self.movementDuration = movementDuration
  }
}
