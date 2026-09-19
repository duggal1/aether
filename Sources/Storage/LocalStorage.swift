import EngineCore
import Foundation
import Synchronization

public final class LocalStorage: Sendable {
  private let values = Mutex<[String: String]>([:])

  public init() {}

  public func get(_ key: String) -> String? { values.withLock { $0[key] } }
  public func set(_ key: String, value: String) { values.withLock { $0[key] = value } }
  public func remove(_ key: String) { _ = values.withLock { $0.removeValue(forKey: key) } }
  public func clear() { values.withLock { $0.removeAll(keepingCapacity: false) } }
  public func snapshot() -> [String: String] { values.withLock { $0 } }
  public func restore(_ snapshot: [String: String]) {
    values.withLock { $0 = snapshot }
  }
  public var count: Int { values.withLock { $0.count } }
}

public final class StoragePartition: Sendable {
  private let stores = Mutex<[String: LocalStorage]>([:])
  public let contextID: ContextID

  public init(contextID: ContextID) {
    self.contextID = contextID
  }

  public func localStorage(for origin: String) -> LocalStorage {
    let key = origin.lowercased()
    return stores.withLock { state in
      if let store = state[key] { return store }
      let store = LocalStorage()
      state[key] = store
      return store
    }
  }

  public func clear(origin: String) {
    _ = stores.withLock { $0.removeValue(forKey: origin.lowercased()) }
  }

  public func clearAll() {
    stores.withLock { $0.removeAll(keepingCapacity: false) }
  }

  public func snapshotAll() -> [String: [String: String]] {
    stores.withLock { state in
      var result: [String: [String: String]] = [:]
      result.reserveCapacity(state.count)
      for (origin, store) in state { result[origin] = store.snapshot() }
      return result
    }
  }

  public func restoreAll(_ snapshot: [String: [String: String]]) {
    stores.withLock { state in
      state.removeAll(keepingCapacity: false)
      for (origin, values) in snapshot {
        let store = LocalStorage()
        store.restore(values)
        state[origin.lowercased()] = store
      }
    }
  }

  public func origins() -> [String] {
    stores.withLock { $0.keys.sorted() }
  }
}
