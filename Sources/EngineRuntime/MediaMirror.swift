import DOM
import EngineCore
import Foundation
import JavaScript
import Media

final class MediaMirror: @unchecked Sendable {  private let lock = NSLock()
  private var values: [NodeID: [String: JSValue]] = [:]

  func set(_ node: NodeID, values: [String: JSValue]) {
    lock.withLock { self.values[node] = values }
  }

  func get(_ node: NodeID) -> [String: JSValue] {
    lock.withLock { values[node] ?? [:] }
  }
}

enum MediaAssignment: Sendable {
  case currentTime(Double)
  case volume(Double)
  case muted(Bool)
  case rate(Double)
}
