import Foundation

public actor WebEventLoop {
  private var microtasks: [@Sendable () async -> Void] = []
  private var tasks: [@Sendable () async -> Void] = []

  public init() {}

  public func queueMicrotask(_ task: @escaping @Sendable () async -> Void) {
    microtasks.append(task)
  }

  public func queueTask(_ task: @escaping @Sendable () async -> Void) {
    tasks.append(task)
  }

  public var pendingMicrotasks: Int { microtasks.count }

  public var pendingTasks: Int { tasks.count }

  public var hasPendingWork: Bool { !microtasks.isEmpty || !tasks.isEmpty }

  public func drain() async {
    while !microtasks.isEmpty {
      let batch = microtasks
      microtasks.removeAll(keepingCapacity: true)
      for task in batch { await task() }
    }
  }

  public func drainTasks() async {
    while !tasks.isEmpty {
      let batch = tasks
      tasks.removeAll(keepingCapacity: true)
      for task in batch { await task() }
      await drain()
    }
  }

  public func drainAll() async {
    await drainTasks()
  }
}
