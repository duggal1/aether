public struct FrameStage: OptionSet, Hashable, Sendable, Codable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let layout = FrameStage(rawValue: 1 << 0)
  public static let paint = FrameStage(rawValue: 1 << 1)
  public static let raster = FrameStage(rawValue: 1 << 2)
  public static let composite = FrameStage(rawValue: 1 << 3)
}

public struct FrameScheduler: Sendable {
  public private(set) var pending: FrameStage
  public private(set) var coalescedRequests: UInt64
  public private(set) var framesScheduled: UInt64
  public private(set) var lastFrameMilliseconds: Double
  public var frameBudgetMilliseconds: Double

  public init(frameBudgetMilliseconds: Double = 8) {
    self.pending = []
    self.coalescedRequests = 0
    self.framesScheduled = 0
    self.lastFrameMilliseconds = 0
    self.frameBudgetMilliseconds = max(0.001, frameBudgetMilliseconds)
  }

  public var isClean: Bool { pending.isEmpty }
  public var isOverBudget: Bool { lastFrameMilliseconds > frameBudgetMilliseconds }

  public mutating func request(_ stage: FrameStage) {
    if !pending.intersection(stage).isEmpty { coalescedRequests &+= 1 }
    pending.formUnion(stage)
  }

  public mutating func takePending() -> FrameStage {
    let taken = pending
    pending = []
    if !taken.isEmpty { framesScheduled &+= 1 }
    return taken
  }

  public mutating func recordFrame(durationMilliseconds: Double) {
    lastFrameMilliseconds = max(0, durationMilliseconds)
  }
}
