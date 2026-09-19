import DOM
import Foundation

public struct JSEventDispatchResult: Hashable, Sendable {
  public var defaultPrevented: Bool

  public init(defaultPrevented: Bool) {
    self.defaultPrevented = defaultPrevented
  }
}

public final class JSEventRegistry {
  private var listeners: [NodeID: [String: [JSFunction]]] = [:]
  var dispatch: ((JSObject, NodeID) -> Bool)?

  func add(_ function: JSFunction, type: String, nodeID: NodeID) {
    let normalized = type.lowercased()
    listeners[nodeID, default: [:]][normalized, default: []].append(function)
  }

  func remove(_ function: JSFunction, type: String, nodeID: NodeID) {
    let normalized = type.lowercased()
    listeners[nodeID]?[normalized]?.removeAll { $0 === function }
    if listeners[nodeID]?[normalized]?.isEmpty == true {
      listeners[nodeID]?.removeValue(forKey: normalized)
    }
    if listeners[nodeID]?.isEmpty == true { listeners.removeValue(forKey: nodeID) }
  }

  func functions(type: String, nodeID: NodeID) -> [JSFunction] {
    listeners[nodeID]?[type.lowercased()] ?? []
  }

  func removeAll(for nodeID: NodeID) {
    listeners.removeValue(forKey: nodeID)
  }
}

final class JSEventState {
  var defaultPrevented = false
  var propagationStopped = false
  var immediateStopped = false
}
