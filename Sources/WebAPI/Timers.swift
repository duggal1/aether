import Foundation

public actor WebTimerManager {
  private var tasks: [UInt64: Task<Void, Never>] = [:]
  private var nextID: UInt64 = 1

  public init() {}

  public func setTimeout(milliseconds: UInt64, operation: @escaping @Sendable () async -> Void)
    -> UInt64
  {
    let id = nextID
    nextID &+= 1
    tasks[id] = Task {
      try? await Task.sleep(for: .milliseconds(milliseconds))
      guard !Task.isCancelled else { return }
      await operation()
      self.finished(id)
    }
    return id
  }

  public func clearTimeout(_ id: UInt64) {
    tasks.removeValue(forKey: id)?.cancel()
  }

  private func finished(_ id: UInt64) {
    tasks.removeValue(forKey: id)
  }
}
