import Foundation

public enum EnginePriority: Int, Hashable, Sendable, Codable, CaseIterable {
  case interaction = 0
  case visibleRendering = 1
  case navigation = 2
  case visibleResource = 3
  case backgroundJavaScript = 4
  case background = 5
}

public actor EngineScheduler {
  private struct Job: Sendable {
    var id: UInt64
    var priority: EnginePriority
    var operation: @Sendable () async -> Void
  }

  private var queues: [EnginePriority: [Job]] = [:]
  private var nextID: UInt64 = 1
  private var draining = false

  public init() {}

  @discardableResult
  public func submit(priority: EnginePriority, operation: @escaping @Sendable () async -> Void)
    -> UInt64
  {
    let id = nextID
    nextID &+= 1
    queues[priority, default: []].append(Job(id: id, priority: priority, operation: operation))
    if !draining {
      draining = true
      Task { await drain() }
    }
    return id
  }

  public func cancel(_ id: UInt64) {
    for priority in EnginePriority.allCases {
      queues[priority]?.removeAll { $0.id == id }
    }
  }

  private func drain() async {
    while let job = popNext() {
      await job.operation()
      await Task.yield()
    }
    draining = false
  }

  private func popNext() -> Job? {
    for priority in EnginePriority.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
      if var queue = queues[priority], !queue.isEmpty {
        let job = queue.removeFirst()
        queues[priority] = queue
        return job
      }
    }
    return nil
  }
}
