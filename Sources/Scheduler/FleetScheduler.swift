import Foundation

public enum FleetAction: String, Hashable, Sendable, Codable {
  case keep
  case suspend
  case freeze
  case discard
}

public struct FleetCandidate: Hashable, Sendable {
  public var page: UInt64
  public var importance: Double
  public var lastActive: Double
  public var estimatedBytes: Int
  public var pinned: Bool

  public init(
    page: UInt64, importance: Double, lastActive: Double, estimatedBytes: Int, pinned: Bool = false
  ) {
    self.page = page
    self.importance = importance
    self.lastActive = lastActive
    self.estimatedBytes = estimatedBytes
    self.pinned = pinned
  }
}

public struct FleetPlan: Hashable, Sendable {
  public var actions: [UInt64: FleetAction]

  public init(actions: [UInt64: FleetAction] = [:]) {
    self.actions = actions
  }

  public func action(for page: UInt64) -> FleetAction { actions[page] ?? .keep }
}

public enum FleetScheduler {
  public static func plan(
    candidates: [FleetCandidate], maxActive: Int, memoryBudgetBytes: Int, now: Double
  ) -> FleetPlan {
    let ranked = candidates.sorted {
      if $0.pinned != $1.pinned { return $0.pinned && !$1.pinned }
      if $0.importance != $1.importance { return $0.importance > $1.importance }
      return $0.lastActive > $1.lastActive
    }
    var actions: [UInt64: FleetAction] = [:]
    var activeCount = 0
    var retainedBytes = 0
    for candidate in ranked {
      if candidate.pinned {
        actions[candidate.page] = .keep
        activeCount += 1
        retainedBytes += max(0, candidate.estimatedBytes)
        continue
      }
      let withinCount = activeCount < max(1, maxActive)
      let withinMemory = retainedBytes + max(0, candidate.estimatedBytes) <= max(
        1, memoryBudgetBytes)
      if withinCount && withinMemory {
        actions[candidate.page] = .keep
        activeCount += 1
        retainedBytes += max(0, candidate.estimatedBytes)
        continue
      }
      let idle = max(0, now - candidate.lastActive)
      if idle > 600 || candidate.estimatedBytes <= 0 {
        actions[candidate.page] = .discard
      } else if idle > 120 {
        actions[candidate.page] = .freeze
      } else {
        actions[candidate.page] = .suspend
      }
    }
    return FleetPlan(actions: actions)
  }

  public static func importance(
    isForeground: Bool, hasPendingNetwork: Bool, hasPendingTimers: Bool, isAudible: Bool = false
  ) -> Double {
    var score = 0.0
    if isForeground { score += 100 }
    if hasPendingNetwork { score += 40 }
    if hasPendingTimers { score += 20 }
    if isAudible { score += 10 }
    return score
  }
}
