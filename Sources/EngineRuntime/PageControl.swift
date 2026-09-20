import DOM
import EngineCore
import Foundation

public enum ControlActorKind: String, Hashable, Sendable, Codable {
  case human
  case agent
}

public struct ControlActor: Hashable, Sendable, Codable {
  public var kind: ControlActorKind
  public var label: String

  public init(kind: ControlActorKind, label: String) {
    self.kind = kind
    self.label = label
  }
}

public struct ControlEvent: Hashable, Sendable, Codable {
  public var sequence: UInt64
  public var timestamp: Double
  public var actorKind: String
  public var actorLabel: String
  public var operation: String
  public var nodeID: NodeID?
  public var outcome: String
  public var error: String?
  public var detail: String?

  public init(
    sequence: UInt64, timestamp: Double, actorKind: String, actorLabel: String,
    operation: String, nodeID: NodeID?, outcome: String, error: String?, detail: String?
  ) {
    self.sequence = sequence
    self.timestamp = timestamp
    self.actorKind = actorKind
    self.actorLabel = actorLabel
    self.operation = operation
    self.nodeID = nodeID
    self.outcome = outcome
    self.error = error
    self.detail = detail
  }
}

public enum PageControlError: Error, Equatable, Sendable {
  case inputHeld(ControlActor)
  case paused
  case approvalRequired(String)
}
