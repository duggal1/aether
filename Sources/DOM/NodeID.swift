import EngineCore

public struct NodeID: Hashable, Sendable, Codable, CustomStringConvertible {
  public let generation: GenerationID

  public init(index: UInt32, generation: UInt32) {
    self.generation = GenerationID(index: index, generation: generation)
  }

  public var index: UInt32 { generation.index }
  public var version: UInt32 { generation.generation }
  public var description: String { "\(index):\(version)" }
}
