import DOM
import EngineCore
import Foundation
import JavaScript
import Media

public final class JSMediaBridge: JSMediaHost, @unchecked Sendable {
  public var snapshot: ((NodeID) -> [String: JSValue])?
  public var play:
    ((NodeID, (@Sendable (Bool, String?) -> Void)?) -> Void)?
  public var pause: ((NodeID) -> Void)?
  public var seek: ((NodeID, Double, (@Sendable (Bool) -> Void)?) -> Void)?
  public var setValue: ((NodeID, String, JSValue) -> Void)?
  public var reload: ((NodeID) -> Void)?

  public init() {}

  public func mediaSnapshot(node: NodeID) -> [String: JSValue] {
    snapshot?(node) ?? [:]
  }

  public func mediaSet(node: NodeID, name: String, value: JSValue) {
    if name == "load" {
      reload?(node)
      return
    }
    setValue?(node, name, value)
  }

  public func mediaPlay(node: NodeID, completion: (@Sendable (Bool, String?) -> Void)?) {
    guard let play else {
      completion?(false, "media unavailable")
      return
    }
    play(node, completion)
  }

  public func mediaPause(node: NodeID) {
    pause?(node)
  }

  public func mediaSeek(node: NodeID, seconds: Double, completion: (@Sendable (Bool) -> Void)?) {
    guard let seek else {
      completion?(false)
      return
    }
    seek(node, seconds, completion)
  }

  public func mediaCanPlayType(node: NodeID, mime: String) -> String {
    let tag: String
    if case .string(let value) = snapshot?(node)["tag"] { tag = value } else { tag = "video" }
    return MediaFormat.canPlayType(mime: mime, tag: tag)
  }

  public static func stateValues(_ state: MediaElementState) -> [String: JSValue] {
    var values: [String: JSValue] = [
      "currentTime": .number(state.currentTime),
      "duration": .number(state.duration),
      "volume": .number(state.volume),
      "playbackRate": .number(state.playbackRate),
      "paused": .bool(state.paused),
      "muted": .bool(state.muted),
      "ended": .bool(state.ended),
      "seeking": .bool(state.seeking),
      "loop": .bool(false),
      "readyState": .number(Double(state.readyState.rawValue)),
      "networkState": .number(Double(state.networkState.rawValue)),
      "videoWidth": .number(Double(state.videoWidth)),
      "videoHeight": .number(Double(state.videoHeight)),
      "currentSrc": .string(state.currentSrc ?? ""),
      "src": .string(state.currentSrc ?? ""),
    ]
    if let error = state.error {
      let object = JSObject()
      object.set("code", .number(Double(error.code.rawValue)))
      object.set("message", .string(error.message))
      values["error"] = .object(object)
    } else {
      values["error"] = .null
    }
    return values
  }
}
