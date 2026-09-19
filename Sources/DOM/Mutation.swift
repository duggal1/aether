import Foundation

public enum DOMMutationType: String, Hashable, Sendable, Codable {
  case nodeCreated
  case nodeRemoved
  case childListChanged
  case attributesChanged
  case characterDataChanged
}

public struct DOMMutation: Hashable, Sendable, Codable {
  public var version: UInt64
  public var type: DOMMutationType
  public var target: NodeID
  public var relatedNode: NodeID?
  public var attributeName: String?

  public init(
    version: UInt64, type: DOMMutationType, target: NodeID, relatedNode: NodeID? = nil,
    attributeName: String? = nil
  ) {
    self.version = version
    self.type = type
    self.target = target
    self.relatedNode = relatedNode
    self.attributeName = attributeName
  }
}
