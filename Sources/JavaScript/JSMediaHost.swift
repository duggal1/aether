import DOM
import EngineCore
import Foundation

public protocol JSMediaHost: AnyObject {
  func mediaSnapshot(node: NodeID) -> [String: JSValue]
  func mediaSet(node: NodeID, name: String, value: JSValue)
  func mediaPlay(node: NodeID, completion: (@Sendable (Bool, String?) -> Void)?)
  func mediaPause(node: NodeID)
  func mediaSeek(node: NodeID, seconds: Double, completion: (@Sendable (Bool) -> Void)?)
  func mediaCanPlayType(node: NodeID, mime: String) -> String
}
