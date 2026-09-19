import Foundation

public protocol EngineIdentifier: Hashable, Sendable, Codable, CustomStringConvertible {
  var rawValue: UInt64 { get }
  init(rawValue: UInt64)
}

extension EngineIdentifier {
  public var description: String { String(rawValue) }
}

public struct DocumentID: EngineIdentifier {
  public let rawValue: UInt64
  public init(rawValue: UInt64) { self.rawValue = rawValue }
}

public struct FrameID: EngineIdentifier {
  public let rawValue: UInt64
  public init(rawValue: UInt64) { self.rawValue = rawValue }
}

public struct ContextID: EngineIdentifier {
  public let rawValue: UInt64
  public init(rawValue: UInt64) { self.rawValue = rawValue }
}

public struct PageID: EngineIdentifier {
  public let rawValue: UInt64
  public init(rawValue: UInt64) { self.rawValue = rawValue }
}

public struct NavigationID: EngineIdentifier {
  public let rawValue: UInt64
  public init(rawValue: UInt64) { self.rawValue = rawValue }
}

public struct RequestID: EngineIdentifier {
  public let rawValue: UInt64
  public init(rawValue: UInt64) { self.rawValue = rawValue }
}

public struct ResponseID: EngineIdentifier {
  public let rawValue: UInt64
  public init(rawValue: UInt64) { self.rawValue = rawValue }
}

public struct DownloadID: EngineIdentifier {
  public let rawValue: UInt64
  public init(rawValue: UInt64) { self.rawValue = rawValue }
}

public struct WorkerID: EngineIdentifier {
  public let rawValue: UInt64
  public init(rawValue: UInt64) { self.rawValue = rawValue }
}

public struct DialogID: EngineIdentifier {
  public let rawValue: UInt64
  public init(rawValue: UInt64) { self.rawValue = rawValue }
}

public struct SessionID: EngineIdentifier {
  public let rawValue: UInt64
  public init(rawValue: UInt64) { self.rawValue = rawValue }
}

public struct GenerationID: Hashable, Sendable, Codable {
  public let index: UInt32
  public let generation: UInt32

  public init(index: UInt32, generation: UInt32) {
    self.index = index
    self.generation = generation
  }
}
